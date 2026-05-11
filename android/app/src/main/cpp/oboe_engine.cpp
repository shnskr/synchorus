// Oboe 네이티브 오디오 엔진 — 스트리밍 디코드 + seek 지원.
// NDK AMediaCodec으로 디코딩 → int16 버퍼 → Oboe float 출력.
// 전체 파일 디코드를 기다리지 않고, 최소 버퍼(1초) 디코드 후 즉시 재생 가능.
// seek 시 해당 위치부터 디코드 → 나머지 갭은 백그라운드에서 채움 (Method A).

#include <oboe/Oboe.h>
#include <jni.h>
#include <android/log.h>
#include <time.h>
#include <atomic>
#include <cmath>
#include <memory>
#include <mutex>
#include <vector>
#include <algorithm>
#include <thread>
#include <condition_variable>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <media/NdkMediaExtractor.h>
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaFormat.h>

#define LOG_TAG "OboeEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

// 1초 분량 디코드 후 loadFile 반환 (48kHz 기준 ~48000 프레임)
static constexpr int64_t MIN_PLAYBACK_FRAMES = 48000;

// §G G-1 ring buffer (2026-05-11): 60초 분량 사전할당, behind 10s + ahead 50s.
// 곡 길이와 무관하게 메모리 일정 (48kHz 스테레오 ≈ 11.5MB).
// behindSeconds = 짧은 rewind 흡수용, aheadSeconds = 디코드 여유 마진.
static constexpr int kRingSeconds = 60;
static constexpr int kRingBehindSeconds = 10;
static constexpr int kRingAheadSeconds = 50;
static_assert(kRingBehindSeconds + kRingAheadSeconds == kRingSeconds,
              "ring buffer 분배 합 = 총 윈도우");

class OboeEngine : public oboe::AudioStreamDataCallback {
public:
    ~OboeEngine() {
        stopDecodeThread();
        stop();
    }

    const std::string& lastError() const { return mLastError; }

    bool loadFile(const char* path) {
        // 기존 디코드 스레드 + 재생 정지
        stopDecodeThread();
        stop();
        resetState();

        // ---- 파일 열기 ----
        int fd = open(path, O_RDONLY);
        if (fd < 0) {
            LOGE("loadFile: open failed: %s", path);
            mLastError = "FILE_OPEN_FAILED";
            return false;
        }
        struct stat st;
        fstat(fd, &st);

        AMediaExtractor* extractor = AMediaExtractor_new();
        media_status_t status = AMediaExtractor_setDataSourceFd(
            extractor, fd, 0, st.st_size);
        close(fd);

        if (status != AMEDIA_OK) {
            LOGE("loadFile: setDataSourceFd: %d", status);
            mLastError = "UNSUPPORTED_FORMAT";
            AMediaExtractor_delete(extractor);
            return false;
        }

        // ---- 오디오 트랙 찾기 ----
        int trackCount = AMediaExtractor_getTrackCount(extractor);
        int audioTrack = -1;
        AMediaFormat* format = nullptr;
        const char* mime = nullptr;

        for (int i = 0; i < trackCount; i++) {
            AMediaFormat* fmt = AMediaExtractor_getTrackFormat(extractor, i);
            const char* m = nullptr;
            AMediaFormat_getString(fmt, AMEDIAFORMAT_KEY_MIME, &m);
            if (m && strncmp(m, "audio/", 6) == 0) {
                audioTrack = i;
                format = fmt;
                mime = m;
                break;
            }
            AMediaFormat_delete(fmt);
        }

        if (audioTrack < 0) {
            LOGE("loadFile: no audio track");
            mLastError = "NO_AUDIO_TRACK";
            AMediaExtractor_delete(extractor);
            return false;
        }

        AMediaExtractor_selectTrack(extractor, audioTrack);

        int32_t sampleRate = 44100;
        int32_t channelCount = 2;
        int64_t durationUs = 0;
        AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_SAMPLE_RATE, &sampleRate);
        AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &channelCount);
        AMediaFormat_getInt64(format, AMEDIAFORMAT_KEY_DURATION, &durationUs);

        LOGI("loadFile: sr=%d ch=%d dur=%.1fs mime=%s",
             sampleRate, channelCount,
             static_cast<double>(durationUs) / 1e6, mime);

        // ---- 코덱 생성 ----
        AMediaCodec* codec = AMediaCodec_createDecoderByType(mime);
        if (!codec) {
            LOGE("loadFile: createDecoder failed: %s", mime);
            mLastError = "UNSUPPORTED_CODEC";
            AMediaFormat_delete(format);
            AMediaExtractor_delete(extractor);
            return false;
        }

        status = AMediaCodec_configure(codec, format, nullptr, nullptr, 0);
        AMediaFormat_delete(format);
        format = nullptr;

        if (status != AMEDIA_OK) {
            LOGE("loadFile: configure: %d", status);
            AMediaCodec_delete(codec);
            AMediaExtractor_delete(extractor);
            return false;
        }

        status = AMediaCodec_start(codec);
        if (status != AMEDIA_OK) {
            LOGE("loadFile: codec start: %d", status);
            AMediaCodec_delete(codec);
            AMediaExtractor_delete(extractor);
            return false;
        }

        // ---- §G G-1: ring buffer 사전 할당 (60s 고정, silence) ----
        // 이전 동작: 곡 전체 사전할당 (5분 ≈ 58MB, 14분 한도). 현행: 60s 고정 (~11.5MB).
        // 곡 길이 무제한 (TOO_LONG 제거).
        int64_t estFrames = (durationUs * sampleRate) / 1000000LL;
        mRingCapacityFrames = static_cast<int64_t>(sampleRate) * kRingSeconds;
        const int64_t ringSamples = mRingCapacityFrames * channelCount;
        mDecodedData.assign(static_cast<size_t>(ringSamples), int16_t(0));
        mDecodedBufSize = static_cast<int64_t>(mDecodedData.size());

        // ---- 메타데이터 설정 ----
        mDecodedChannels = channelCount;
        mDecodedSampleRate = sampleRate;
        mDecodedTotalFrames = estFrames;
        mVirtualFrame.store(0, std::memory_order_relaxed);

        // ---- 스트리밍 디코드 상태 초기화 ----
        mDecodeAbort.store(false, std::memory_order_relaxed);
        mDecodeSeekTarget.store(-1, std::memory_order_relaxed);
        mRingHead.store(0, std::memory_order_relaxed);
        mRingTail.store(0, std::memory_order_relaxed);
        mDecodedFrameCount.store(0, std::memory_order_relaxed);

        // 파일 로드 완료 표시 (onAudioReady에서 접근 허용)
        mFileLoaded = true;

        // ---- 백그라운드 디코드 스레드 시작 ----
        mDecoding.store(true, std::memory_order_release);
        mDecodeThread = std::thread(
            &OboeEngine::decodeLoop, this,
            extractor, codec, channelCount, sampleRate);

        // ---- 최소 버퍼 대기 (1초 또는 파일 전체) ----
        waitForMinBuffer(estFrames);

        LOGI("loadFile: streaming decode started, %lld est frames, %.1fs",
             static_cast<long long>(estFrames),
             static_cast<double>(estFrames) / sampleRate);

        return true;
    }

    // stream을 미리 만들고 requestStart까지 수행하되, mPrewarmIdle=true로 콜백을
    // 무음 + vf 동결 모드로 만든다. 다음 start()에서 flag만 풀면 즉시 정상 출력 →
    // BT codec/HAL 워밍업 + outputLatency 안정값 수렴이 미리 끝나 있음. (v0.0.44)
    bool prewarm() {
        std::lock_guard<std::mutex> lock(mLock);
        if (mStream) {
            LOGI("prewarm: stream already exists, returning true");
            return true;
        }
        if (!mFileLoaded) {
            LOGE("prewarm: no file loaded");
            return false;
        }
        // start() 시 콜백이 정상 동작하도록 false로 시작 — 그 후 release-store로
        // true 설정 (콜백이 캐시한 값을 못 읽도록).
        mPrewarmIdle.store(true, std::memory_order_release);

        oboe::AudioStreamBuilder builder;
        oboe::Result result = builder
            .setDirection(oboe::Direction::Output)
            ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
            ->setSharingMode(oboe::SharingMode::Exclusive)
            ->setFormat(oboe::AudioFormat::Float)
            ->setChannelCount(oboe::ChannelCount::Stereo)
            ->setSampleRate(mDecodedSampleRate)
            ->setSampleRateConversionQuality(
                oboe::SampleRateConversionQuality::Medium)
            ->setDataCallback(this)
            ->openStream(mStream);

        if (result != oboe::Result::OK) {
            LOGE("prewarm openStream: %s", oboe::convertToText(result));
            mStream.reset();
            mPrewarmIdle.store(false, std::memory_order_relaxed);
            return false;
        }

        mStreamSampleRate = mStream->getSampleRate();
        LOGI("prewarm stream OK: reqSR=%d actualSR=%d burst=%d",
             mDecodedSampleRate, mStreamSampleRate,
             mStream->getFramesPerBurst());

        result = mStream->requestStart();
        if (result != oboe::Result::OK) {
            LOGE("prewarm requestStart: %s", oboe::convertToText(result));
            mStream->close();
            mStream.reset();
            mPrewarmIdle.store(false, std::memory_order_relaxed);
            return false;
        }
        return true;
    }

    bool start() {
        // v0.0.46: pause/resume 모델. stop()이 close + reset 안 하고 pause만 함.
        // 이미 stream 있으면 requestStart로 재개 (setup latency 0 — Android edge case
        // (42) fix: 정지/재생 시 stream 새로 open 안 해 게스트가 즉시 출력).
        // 첫 호출 또는 unload 후엔 stream 새로 open.
        std::lock_guard<std::mutex> lock(mLock);
        if (mStream) {
            // v0.0.72: file sample rate가 stream actualSR과 다르면 stream 재생성.
            // 첫 파일 44100Hz로 stream 열린 후 두 번째 파일 48000Hz 로드 시 stream
            // 그대로 두면 file 데이터를 wrong rate hardware로 보내 음정 0.919배
            // (반음 정도 낮음) 효과 발생 (HISTORY (85)).
            if (mStreamSampleRate > 0 && mDecodedSampleRate > 0 &&
                mStreamSampleRate != mDecodedSampleRate) {
                LOGI("start: stream SR mismatch (stream=%d, file=%d) → reopen",
                     mStreamSampleRate, mDecodedSampleRate);
                mStream->stop();
                mStream->close();
                mStream.reset();
                mStreamSampleRate = 0;
                // fall through to prewarmInternal_locked below
            } else {
                mPrewarmIdle.store(false, std::memory_order_release);
                // pause 상태면 resume. 이미 active면 무해.
                if (mStream->getState() == oboe::StreamState::Paused ||
                    mStream->getState() == oboe::StreamState::Pausing) {
                    oboe::Result result = mStream->requestStart();
                    if (result != oboe::Result::OK) {
                        LOGE("start (resume): %s", oboe::convertToText(result));
                        return false;
                    }
                }
                return true;
            }
        }
        if (!mFileLoaded) {
            LOGE("start: no file loaded");
            return false;
        }
        // prewarm은 mLock을 잡으므로 lock 풀고 호출.
        // (mStream 없는 게 확정이므로 race 없음 — Dart 측에서 직렬 호출.)
        return prewarmInternal_locked();
    }

private:
    // start 내부에서 호출 (lock 이미 잡혀있음).
    bool prewarmInternal_locked() {
        if (mStream) {
            return true;
        }
        if (!mFileLoaded) return false;
        mPrewarmIdle.store(false, std::memory_order_release);

        oboe::AudioStreamBuilder builder;
        oboe::Result result = builder
            .setDirection(oboe::Direction::Output)
            ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
            ->setSharingMode(oboe::SharingMode::Exclusive)
            ->setFormat(oboe::AudioFormat::Float)
            ->setChannelCount(oboe::ChannelCount::Stereo)
            ->setSampleRate(mDecodedSampleRate)
            ->setSampleRateConversionQuality(
                oboe::SampleRateConversionQuality::Medium)
            ->setDataCallback(this)
            ->openStream(mStream);

        if (result != oboe::Result::OK) {
            LOGE("start openStream: %s", oboe::convertToText(result));
            mStream.reset();
            return false;
        }

        mStreamSampleRate = mStream->getSampleRate();
        LOGI("start stream OK: reqSR=%d actualSR=%d burst=%d",
             mDecodedSampleRate, mStreamSampleRate,
             mStream->getFramesPerBurst());

        // v0.0.74-fix: 새 stream 활성화 시 진단 카운터 reset
        mLatDiagCount = 0;

        result = mStream->requestStart();
        if (result != oboe::Result::OK) {
            LOGE("start requestStart: %s", oboe::convertToText(result));
            mStream->close();
            mStream.reset();
            return false;
        }
        return true;
    }
public:

    // v0.0.46 (42) fix: pause/resume 모델. stream을 close하지 않고 pause만 함.
    // 다음 start() 시 stream 새로 open 안 해 setup latency 0 → 정지/재생 시
    // 게스트가 즉시 출력 (HISTORY (42) edge case). 진짜 close는 unload()에서.
    bool stop() {
        std::lock_guard<std::mutex> lock(mLock);
        if (!mStream) return true;
        if (mStream->getState() == oboe::StreamState::Started ||
            mStream->getState() == oboe::StreamState::Starting) {
            oboe::Result result = mStream->requestPause();
            if (result != oboe::Result::OK) {
                LOGE("stop (pause): %s", oboe::convertToText(result));
                // pause 실패 시 close + reset으로 fallback.
                mStream->requestStop();
                mStream->close();
                mStream.reset();
            }
        }
        mPrewarmIdle.store(false, std::memory_order_relaxed);
        return true;
    }

    // 완전 close (방 나가기 / 새 파일 로드 시 unload에서 호출).
    bool fullStop() {
        std::lock_guard<std::mutex> lock(mLock);
        if (!mStream) return true;
        mStream->requestStop();
        mStream->close();
        mStream.reset();
        mPrewarmIdle.store(false, std::memory_order_relaxed);
        return true;
    }

    // idle 자동 해제용. v0.0.46 기준 stop과 동일 (호출은 dead path).
    bool coolDown() {
        return stop();
    }

    bool unload() {
        // v0.0.46: stop은 pause만 하므로 unload에선 진짜 close 필요.
        fullStop();
        stopDecodeThread();
        resetState();
        mVirtualFrame.store(0, std::memory_order_relaxed);
        return true;
    }

    bool getLatestTimestamp(
        int64_t* outFramePos,
        int64_t* outTimeNs,
        int64_t* outWallAtFramePosNs,
        int64_t* outVirtualFrame,
        double* outOutputLatencyMs) {

        // virtualFrame은 항상 유효 (오디오 콜백이 매 프레임 갱신)
        *outVirtualFrame = mVirtualFrame.load(std::memory_order_relaxed);

        // wall clock도 항상 제공 (fallback sync에 사용)
        struct timespec wallTs, monoTs;
        clock_gettime(CLOCK_REALTIME, &wallTs);
        clock_gettime(CLOCK_MONOTONIC, &monoTs);
        const int64_t wallNow =
            static_cast<int64_t>(wallTs.tv_sec) * 1000000000LL + wallTs.tv_nsec;
        const int64_t monoNow =
            static_cast<int64_t>(monoTs.tv_sec) * 1000000000LL + monoTs.tv_nsec;

        // outputLatencyMs default: -1 (미지원/측정 불가). Dart에서 sanity check.
        // BT codec/radio 단계는 Oboe 가이드상 잘 안 잡힘 — 어디까지 보고되는지는
        // 디바이스/HAL 의존. 그래도 OS가 알고 있는 만큼은 drift 공식 보정에 활용.
        *outOutputLatencyMs = -1.0;

        std::lock_guard<std::mutex> lock(mLock);
        if (!mStream) {
            *outFramePos = -1;
            *outTimeNs = -1;
            *outWallAtFramePosNs = wallNow;
            return false;
        }

        auto latRes = mStream->calculateLatencyMillis();
        bool latAbnormal = false;
        if (latRes) {
            *outOutputLatencyMs = latRes.value();
            // v0.0.74-fix 진단: 비정상값 (음수=clock skew Issue #678, >500=outlier).
            // 정상값 도달 시점 추적용. 안정 도달까지 첫 N회 + 그 후 spam 방지 throttle.
            if (latRes.value() < 0 || latRes.value() > 500) {
                latAbnormal = true;
            }
        } else {
            latAbnormal = true;
        }
        if (latAbnormal) {
            // 첫 5회 + 그 후 매 50회마다 (25Hz 폴링이면 2초마다)
            if (mLatDiagCount < 5 || mLatDiagCount % 50 == 0) {
                if (latRes) {
                    LOGW("calcLatency abnormal[%d]: %.2fms",
                         mLatDiagCount, latRes.value());
                } else {
                    LOGW("calcLatency abnormal[%d]: %s",
                         mLatDiagCount, oboe::convertToText(latRes.error()));
                }
            }
            mLatDiagCount++;
        } else if (mLatDiagCount > 0) {
            // 안정 도달 — 누적 비정상 횟수 보고 후 reset
            LOGI("calcLatency recovered after %d abnormal: %.2fms",
                 mLatDiagCount, latRes.value());
            mLatDiagCount = 0;
        }

        int64_t framePos = 0;
        int64_t timeNs = 0;
        oboe::Result result = mStream->getTimestamp(
            CLOCK_MONOTONIC, &framePos, &timeNs);
        if (result != oboe::Result::OK) {
            if (mLastTsResult == oboe::Result::OK) {
                auto xrunRes = mStream->getXRunCount();
                mTsFailStreakStartXRun = xrunRes ? xrunRes.value() : -1;
                mTsFailStreakStartMonoNs = monoNow;
                mTsFailStreakCount = 0;
                LOGW("getTimestamp streak start: %s (%d) state=%s xrun=%d wallMs=%lld",
                     oboe::convertToText(result), static_cast<int>(result),
                     oboe::convertToText(mStream->getState()),
                     mTsFailStreakStartXRun,
                     static_cast<long long>(wallNow / 1000000LL));
            }
            ++mTsFailStreakCount;
            mLastTsResult = result;
            *outFramePos = -1;
            *outTimeNs = -1;
            *outWallAtFramePosNs = wallNow;
            return false;
        }
        if (mLastTsResult != oboe::Result::OK) {
            auto xrunEndRes = mStream->getXRunCount();
            int32_t xrunEnd = xrunEndRes ? xrunEndRes.value() : -1;
            int32_t xrunDelta =
                (xrunEnd >= 0 && mTsFailStreakStartXRun >= 0)
                    ? xrunEnd - mTsFailStreakStartXRun
                    : -1;
            const int64_t durMs =
                (monoNow - mTsFailStreakStartMonoNs) / 1000000LL;
            LOGW("getTimestamp streak end: last=%s count=%lld duration=%lldms state=%s xrunDelta=%d wallMs=%lld",
                 oboe::convertToText(mLastTsResult),
                 static_cast<long long>(mTsFailStreakCount),
                 static_cast<long long>(durMs),
                 oboe::convertToText(mStream->getState()),
                 xrunDelta,
                 static_cast<long long>(wallNow / 1000000LL));
        }
        mLastTsResult = oboe::Result::OK;

        // HAL framePos는 스트림 rate(예: 48kHz)로 카운트되지만
        // VF/totalFrames/sampleRate는 파일 rate(예: 44.1kHz).
        // 일관성을 위해 framePos도 파일 rate로 변환.
        if (mStreamSampleRate > 0 && mDecodedSampleRate > 0 &&
            mStreamSampleRate != mDecodedSampleRate) {
            framePos = framePos * mDecodedSampleRate / mStreamSampleRate;
        }
        *outFramePos = framePos;
        *outTimeNs = timeNs;
        *outWallAtFramePosNs = wallNow - (monoNow - timeNs);
        return true;
    }

    int64_t getVirtualFrame() const {
        return mVirtualFrame.load(std::memory_order_relaxed);
    }

    void setMuted(bool muted) {
        mMuted.store(muted, std::memory_order_relaxed);
    }

    bool isMuted() const {
        return mMuted.load(std::memory_order_relaxed);
    }

    /// NTP-style 예약 재생 (v0.0.47). data callback 안에서 wall clock과 비교 →
    /// 예약 시각 도달 시 정상 출력 시작 (그 전엔 silent + vf 동결).
    /// 양쪽이 같은 wallEpochMs를 약속해 동시 출력 시작 → anchor 의존 제거.
    bool scheduleStart(int64_t wallEpochMs, int64_t fromFrame) {
        if (!mFileLoaded) {
            LOGE("scheduleStart: no file loaded");
            return false;
        }

        // 시작 frame 미리 갱신 (silent 동안 동결됨, 도달 시 +elapsed 보정)
        int64_t clamped = std::max(int64_t(0), std::min(fromFrame, mDecodedTotalFrames));
        mVirtualFrame.store(clamped, std::memory_order_relaxed);
        mScheduledStartFromFrame.store(clamped, std::memory_order_relaxed);

        // 시작 wall ns 등록
        mScheduledStartWallNs.store(wallEpochMs * 1000000LL, std::memory_order_release);
        mScheduledStartActive.store(true, std::memory_order_release);

        // stream 보장 (없으면 새로 open + start, 있으면 resume)
        bool ok = start();
        if (!ok) {
            mScheduledStartActive.store(false, std::memory_order_relaxed);
            LOGE("scheduleStart: start() failed");
            return false;
        }
        LOGI("scheduleStart: wallMs=%lld fromFrame=%lld",
             static_cast<long long>(wallEpochMs),
             static_cast<long long>(clamped));
        return true;
    }

    /// 진행 중인 schedule 취소 + 출력 정지 (pause 모델).
    bool cancelSchedule() {
        mScheduledStartActive.store(false, std::memory_order_relaxed);
        return stop();
    }

    bool seekToFrame(int64_t newFrame) {
        if (!mFileLoaded) return false;
        int64_t clamped = std::max(
            int64_t(0), std::min(newFrame, mDecodedTotalFrames));
        mVirtualFrame.store(clamped, std::memory_order_relaxed);

        // §G G-1 ring buffer seek 분기:
        // - 윈도우 안 (drift 보정 등 작은 seek): vf만 갱신 → 즉시 (디코드 wait 0)
        // - 윈도우 밖 (사용자 슬라이더 큰 seek): head/tail reset + 디코드 점프
        if (!isFrameDecoded(clamped)) {
            // 윈도우 밖 → ring 리셋 후 새 위치부터 디코드 시작
            mRingHead.store(clamped, std::memory_order_release);
            mRingTail.store(clamped, std::memory_order_release);
            if (mDecoding.load(std::memory_order_relaxed)) {
                mDecodeSeekTarget.store(clamped, std::memory_order_release);
                // decodeLoop가 wait 중일 수 있음 → 깨움
                std::lock_guard<std::mutex> lock(mRingMutex);
                mRingCv.notify_all();
            }
        }

        return true;
    }

    int32_t getSampleRate() const {
        return mDecodedSampleRate > 0 ? mDecodedSampleRate : 48000;
    }

    int64_t getTotalFrames() const { return mDecodedTotalFrames; }

    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* stream,
        void* audioData,
        int32_t numFrames) override {

        auto* output = static_cast<float*>(audioData);
        const int outCh = stream->getChannelCount();

        if (!mFileLoaded) {
            memset(audioData, 0,
                   static_cast<size_t>(numFrames * outCh) * sizeof(float));
            return oboe::DataCallbackResult::Continue;
        }

        // prewarmed but not playing: 무음 출력 + vf 동결. AAudio/BT codec은
        // 깨어있어 워밍업 효과는 유지되지만 PCM은 0이고 시간도 진행 안 함.
        // start() 시 mPrewarmIdle=false로 전환되면 다음 콜백부터 정상 출력. (v0.0.44)
        if (mPrewarmIdle.load(std::memory_order_acquire)) {
            memset(audioData, 0,
                   static_cast<size_t>(numFrames * outCh) * sizeof(float));
            return oboe::DataCallbackResult::Continue;
        }

        // NTP-style 예약 재생 (v0.0.47): 시작 wall time 도달 전엔 silent + vf 동결.
        // 도달 시 elapsed만큼 vf 보정 후 active=false → 정상 출력.
        if (mScheduledStartActive.load(std::memory_order_acquire)) {
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            int64_t nowWallNs =
                static_cast<int64_t>(ts.tv_sec) * 1000000000LL + ts.tv_nsec;
            int64_t startWallNs =
                mScheduledStartWallNs.load(std::memory_order_relaxed);
            if (nowWallNs < startWallNs) {
                // 아직 시작 시각 안 됨 → silent
                memset(audioData, 0,
                       static_cast<size_t>(numFrames * outCh) * sizeof(float));
                return oboe::DataCallbackResult::Continue;
            }
            // 시작 시각 도달 — elapsed만큼 frame 보정 후 active=false
            int64_t elapsedNs = nowWallNs - startWallNs;
            int64_t elapsedFrames =
                elapsedNs * mDecodedSampleRate / 1000000000LL;
            int64_t fromFrame =
                mScheduledStartFromFrame.load(std::memory_order_relaxed);
            mVirtualFrame.store(fromFrame + elapsedFrames,
                               std::memory_order_relaxed);
            mScheduledStartActive.store(false, std::memory_order_release);
            LOGI("scheduledStart fired: elapsedNs=%lld elapsedFrames=%lld vf=%lld",
                 static_cast<long long>(elapsedNs),
                 static_cast<long long>(elapsedFrames),
                 static_cast<long long>(fromFrame + elapsedFrames));
            // 그 다음 정상 출력 코드 그대로 진행 (아래로 떨어짐)
        }

        const bool muted = mMuted.load(std::memory_order_relaxed);
        int64_t vf = mVirtualFrame.load(std::memory_order_relaxed);

        // §G G-1 ring buffer: 윈도우 [tail, head) 안이면 modular index로 read.
        // 밖이면 무음 (디코드 wait 또는 EOS).
        const int64_t ringHead = mRingHead.load(std::memory_order_acquire);
        const int64_t ringTail = mRingTail.load(std::memory_order_acquire);
        const int64_t totalFrames = mDecodedTotalFrames;
        const int64_t capFrames = mRingCapacityFrames;

        for (int i = 0; i < numFrames; ++i) {
            const bool decoded = vf >= ringTail && vf < ringHead;

            for (int ch = 0; ch < outCh; ++ch) {
                float sample = 0.0f;
                if (!muted && decoded && vf >= 0 && vf < totalFrames && capFrames > 0) {
                    int srcCh = std::min(ch, mDecodedChannels - 1);
                    int64_t bufFrame = vf % capFrames;
                    int64_t idx = bufFrame * mDecodedChannels + srcCh;
                    sample = static_cast<float>(mDecodedData[idx]) / 32768.0f;
                }
                *output++ = sample;
            }
            ++vf;
        }

        mVirtualFrame.store(vf, std::memory_order_relaxed);

        // §G G-1 ring buffer tail advance: 재생 head 진행에 따라 behind 한도 유지.
        // tail = max(tail, vf - behindFrames). atomic 갱신으로 lock 회피.
        // decodeLoop가 polling으로 tail 변화 감지 → buffer 빈 공간 확보.
        if (capFrames > 0) {
            const int64_t behindFrames =
                static_cast<int64_t>(mDecodedSampleRate) * kRingBehindSeconds;
            const int64_t newTail = std::max<int64_t>(0, vf - behindFrames);
            if (newTail > ringTail) {
                mRingTail.store(newTail, std::memory_order_release);
            }
        }
        return oboe::DataCallbackResult::Continue;
    }

private:
    // ---- 재생 상태 ----
    std::shared_ptr<oboe::AudioStream> mStream;
    int32_t mStreamSampleRate = 48000;
    std::atomic<int64_t> mVirtualFrame{0};
    std::atomic<bool> mMuted{false};
    // prewarm 상태에서 콜백을 무음 + vf 동결 모드로 만드는 플래그. (v0.0.44)
    std::atomic<bool> mPrewarmIdle{false};
    // NTP-style 예약 재생 (v0.0.47). active=true이면 콜백이 wall clock과 비교해
    // mScheduledStartWallNs 도달 전엔 silent + vf 동결, 도달 후 elapsed 보정 후 정상 출력.
    std::atomic<bool> mScheduledStartActive{false};
    std::atomic<int64_t> mScheduledStartWallNs{0};
    std::atomic<int64_t> mScheduledStartFromFrame{0};
    std::mutex mLock;

    // getTimestamp 실패 원인 진단용. logcat 폭주를 막기 위해 연속 실패(streak)
    // 시작 시 1회, 종료 시 1회만 로그. 시작 로그: result + stream state + xrun.
    // 종료 로그: 길이 + 지속 시간 + 마지막 result + 종료 시 state + xrun delta.
    // 같은 코드/입력에서 streak 길이가 비결정적이라(HISTORY (30) vs (31)),
    // 다음 긴 streak 발생 시 시스템 상태와 매칭하기 위한 풍부한 컨텍스트.
    oboe::Result mLastTsResult{oboe::Result::OK};
    int64_t mTsFailStreakCount{0};
    int64_t mTsFailStreakStartMonoNs{0};
    int32_t mTsFailStreakStartXRun{-1};

    // v0.0.74-fix: calculateLatencyMillis 비정상값 누적 카운터.
    // stream 활성 직후 -1/음수/>500 보고 패턴 추적. 안정 도달 시 0 reset.
    int64_t mLatDiagCount{0};

    // ---- 디코딩된 오디오 버퍼 (§G G-1 ring buffer) ----
    // mDecodedData = 60s × sampleRate × channels (int16_t). 곡 전체 사전할당
    // (이전 동작) → 60s 고정 (현행). 콘텐츠 frame ↔ buffer index는 modular.
    std::vector<int16_t> mDecodedData;
    int64_t mDecodedBufSize = 0;             // mDecodedData.size() 캐시
    int64_t mRingCapacityFrames = 0;         // sampleRate × kRingSeconds
    int32_t mDecodedChannels = 0;
    int32_t mDecodedSampleRate = 0;
    int64_t mDecodedTotalFrames = 0;
    bool mFileLoaded = false;
    std::string mLastError;

    // ---- ring buffer head/tail (콘텐츠 frame, 절대값) ----
    // 윈도우 = [mRingTail, mRingHead). vf가 이 안이면 read OK.
    // 디코드 스레드: head++ (앞으로 채움). 재생 진행 시 tail 따라 advance.
    // invariant: mRingHead - mRingTail <= mRingCapacityFrames
    std::atomic<int64_t> mRingHead{0};
    std::atomic<int64_t> mRingTail{0};

    // ---- 스트리밍 디코드 상태 ----
    std::thread mDecodeThread;
    std::atomic<bool> mDecoding{false};
    std::atomic<bool> mDecodeAbort{false};
    std::atomic<int64_t> mDecodeSeekTarget{-1};

    // ring buffer 디코드 throttle용. 재생 head가 디코드 head를 따라잡으면
    // wait, 디코드 head가 ahead 한도 도달하면 wait.
    std::mutex mRingMutex;
    std::condition_variable mRingCv;

    // 최소 버퍼 대기용 (loadFile에서 1초 분량 채워지면 반환)
    std::atomic<int64_t> mDecodedFrameCount{0};
    std::mutex mMinBufMutex;
    std::condition_variable mMinBufCv;

    // ---- 헬퍼 ----

    // §G G-1 ring buffer: 윈도우 안 판정 (단일 [tail, head) 비교).
    inline bool isFrameDecoded(int64_t frame) const {
        const int64_t tail = mRingTail.load(std::memory_order_acquire);
        const int64_t head = mRingHead.load(std::memory_order_acquire);
        return frame >= tail && frame < head;
    }

    // 콘텐츠 frame → ring buffer 안 frame index (channels는 호출 측에서 곱).
    // mRingCapacityFrames > 0 보장 후 호출.
    inline int64_t ringFrameIdx(int64_t contentFrame) const {
        return contentFrame % mRingCapacityFrames;
    }

    void stopDecodeThread() {
        mDecodeAbort.store(true, std::memory_order_relaxed);
        {
            std::lock_guard<std::mutex> lock(mMinBufMutex);
            mMinBufCv.notify_all();
        }
        if (mDecodeThread.joinable()) {
            mDecodeThread.join();
        }
        mDecoding.store(false, std::memory_order_relaxed);
    }

    void resetState() {
        mDecodedData.clear();
        mDecodedData.shrink_to_fit();
        mDecodedBufSize = 0;
        mRingCapacityFrames = 0;
        mDecodedChannels = 0;
        mDecodedSampleRate = 0;
        mDecodedTotalFrames = 0;
        mFileLoaded = false;
        mLastError.clear();
        mRingHead.store(0, std::memory_order_relaxed);
        mRingTail.store(0, std::memory_order_relaxed);
        mDecodedFrameCount.store(0, std::memory_order_relaxed);
    }

    void waitForMinBuffer(int64_t totalFrames) {
        int64_t target = std::min(MIN_PLAYBACK_FRAMES, totalFrames);
        std::unique_lock<std::mutex> lock(mMinBufMutex);
        mMinBufCv.wait_for(lock, std::chrono::seconds(5), [&] {
            return mDecodedFrameCount.load(std::memory_order_relaxed) >= target
                || mDecodeAbort.load(std::memory_order_relaxed)
                || !mDecoding.load(std::memory_order_relaxed);
        });
    }

    // ---- §G G-1 ring buffer 백그라운드 디코드 메인 루프 ----
    // extractor, codec의 소유권을 받아 정리까지 책임진다.
    // ring head 진행 → 가득 차면 (head - tail >= capacity) tail 진행 wait.
    // seek 시 head/tail은 seekToFrame에서 reset됨 — decode loop는 codec flush + extractor seek만.
    void decodeLoop(AMediaExtractor* extractor, AMediaCodec* codec,
                    int channelCount, int32_t sampleRate) {

        int64_t writeFrame = 0;
        bool inputEos = false;
        bool outputEos = false;
        bool needsPtsReset = false;

        while (!outputEos && !mDecodeAbort.load(std::memory_order_relaxed)) {
            // ---- seek 요청 확인 ----
            int64_t seekTarget = mDecodeSeekTarget.exchange(
                -1, std::memory_order_acquire);
            if (seekTarget >= 0) {
                LOGI("decode: ring seek to frame %lld",
                     static_cast<long long>(seekTarget));
                AMediaCodec_flush(codec);
                int64_t seekUs =
                    (seekTarget * 1000000LL) / sampleRate;
                AMediaExtractor_seekTo(
                    extractor, seekUs,
                    AMEDIAEXTRACTOR_SEEK_CLOSEST_SYNC);
                inputEos = false;
                outputEos = false;
                needsPtsReset = true;
                writeFrame = seekTarget; // PTS로 보정 예정
                // head/tail은 seekToFrame()에서 이미 reset됨.
            }

            // ---- ring 가득 차면 wait (head - tail >= capacity) ----
            // 재생이 진행되어 tail이 advance되면 깨어남 (또는 짧은 timeout polling).
            // mDecodeSeekTarget 변경 시도 즉시 깨어나야 — 짧은 timeout.
            {
                std::unique_lock<std::mutex> lock(mRingMutex);
                mRingCv.wait_for(lock, std::chrono::milliseconds(50), [&] {
                    if (mDecodeAbort.load(std::memory_order_relaxed)) return true;
                    if (mDecodeSeekTarget.load(std::memory_order_relaxed) >= 0) return true;
                    const int64_t head = mRingHead.load(std::memory_order_relaxed);
                    const int64_t tail = mRingTail.load(std::memory_order_relaxed);
                    return (head - tail) < mRingCapacityFrames;
                });
                if (mDecodeAbort.load(std::memory_order_relaxed)) break;
                if (mDecodeSeekTarget.load(std::memory_order_relaxed) >= 0) {
                    continue; // 다음 루프 첫 머리에서 seek 처리
                }
            }

            // ---- 입력 단계: extractor → codec ----
            if (!inputEos) {
                ssize_t inIdx = AMediaCodec_dequeueInputBuffer(codec, 10000);
                if (inIdx >= 0) {
                    size_t inSize = 0;
                    uint8_t* inBuf = AMediaCodec_getInputBuffer(
                        codec, static_cast<size_t>(inIdx), &inSize);
                    ssize_t read = AMediaExtractor_readSampleData(
                        extractor, inBuf, inSize);

                    if (read < 0) {
                        AMediaCodec_queueInputBuffer(
                            codec, static_cast<size_t>(inIdx),
                            0, 0, 0,
                            AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
                        inputEos = true;
                    } else {
                        int64_t pts = AMediaExtractor_getSampleTime(extractor);
                        AMediaCodec_queueInputBuffer(
                            codec, static_cast<size_t>(inIdx),
                            0, static_cast<size_t>(read), pts, 0);
                        AMediaExtractor_advance(extractor);
                    }
                }
            }

            // ---- 출력 단계: codec → ring buffer ----
            AMediaCodecBufferInfo info;
            ssize_t outIdx = AMediaCodec_dequeueOutputBuffer(codec, &info, 10000);

            if (outIdx >= 0) {
                if (info.size > 0) {
                    // seek 직후 첫 출력: PTS로 정확한 쓰기 위치 설정
                    if (needsPtsReset && info.presentationTimeUs >= 0) {
                        int64_t ptsFrame =
                            (info.presentationTimeUs * sampleRate) / 1000000LL;
                        writeFrame = ptsFrame;
                        // ring head를 PTS 위치로 보정 (seekToFrame이 set한 위치와 약간
                        // 차이날 수 있음 — codec이 sync sample로 고정해서). tail도 같이.
                        mRingHead.store(ptsFrame, std::memory_order_release);
                        mRingTail.store(ptsFrame, std::memory_order_release);
                        needsPtsReset = false;
                    }

                    size_t outSize = 0;
                    uint8_t* outBuf = AMediaCodec_getOutputBuffer(
                        codec, static_cast<size_t>(outIdx), &outSize);
                    int numSamples =
                        info.size / static_cast<int>(sizeof(int16_t));
                    const auto* samples = reinterpret_cast<const int16_t*>(
                        outBuf + info.offset);
                    int numFrames = numSamples / channelCount;

                    // §G G-1 ring buffer write (modular index, wrap-around 시 분할).
                    if (mRingCapacityFrames > 0 && numFrames > 0) {
                        const int64_t startBufFrame = writeFrame % mRingCapacityFrames;
                        const int64_t endBufFrame = (writeFrame + numFrames) % mRingCapacityFrames;
                        const int64_t framesToBufEnd = mRingCapacityFrames - startBufFrame;

                        if (numFrames <= framesToBufEnd) {
                            // wrap 없음, 한 chunk
                            std::copy(samples, samples + numSamples,
                                      mDecodedData.data() + startBufFrame * channelCount);
                        } else {
                            // wrap-around, 두 chunk로 분할
                            const int64_t firstSamples = framesToBufEnd * channelCount;
                            std::copy(samples, samples + firstSamples,
                                      mDecodedData.data() + startBufFrame * channelCount);
                            const int64_t remainingSamples = numSamples - firstSamples;
                            std::copy(samples + firstSamples,
                                      samples + numSamples,
                                      mDecodedData.data());
                            (void)endBufFrame; // unused, debug 시 비교
                        }
                    }

                    writeFrame += numFrames;
                    // ring head advance — onAudioReady는 head load로 윈도우 판정.
                    mRingHead.store(writeFrame, std::memory_order_release);

                    // 최소 버퍼 대기 해제용 카운터
                    mDecodedFrameCount.fetch_add(
                        numFrames, std::memory_order_relaxed);
                    {
                        std::lock_guard<std::mutex> lk(mMinBufMutex);
                        mMinBufCv.notify_one();
                    }
                }

                if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) {
                    outputEos = true;
                }
                AMediaCodec_releaseOutputBuffer(
                    codec, static_cast<size_t>(outIdx), false);

            } else if (outIdx == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
                AMediaFormat* newFmt = AMediaCodec_getOutputFormat(codec);
                AMediaFormat_getInt32(
                    newFmt, AMEDIAFORMAT_KEY_SAMPLE_RATE, &sampleRate);
                AMediaFormat_getInt32(
                    newFmt, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &channelCount);
                LOGI("format changed: sr=%d ch=%d", sampleRate, channelCount);
                AMediaFormat_delete(newFmt);
            }
        }

        // ring buffer는 sliding window라 fillGaps 불필요 (seek 후 그 위치부터 채움).
        // 전체 디코드 완료 시 totalFrames 보정만.
        if (!mDecodeAbort.load(std::memory_order_relaxed)) {
            if (writeFrame > 0 && writeFrame != mDecodedTotalFrames) {
                LOGI("decode: actual frames %lld vs est %lld",
                     static_cast<long long>(writeFrame),
                     static_cast<long long>(mDecodedTotalFrames));
                if (writeFrame < mDecodedTotalFrames) {
                    mDecodedTotalFrames = writeFrame;
                }
            }
        }

        // ---- 정리 ----
        AMediaCodec_stop(codec);
        AMediaCodec_delete(codec);
        AMediaExtractor_delete(extractor);

        mDecoding.store(false, std::memory_order_release);
        LOGI("decode thread done: %lld frames decoded",
             static_cast<long long>(mDecodedFrameCount.load()));
    }

    // §G G-1 ring buffer는 sliding window라 fillGaps 불필요 (제거됨).
    // 이전 동작 (사전할당 + seek-in-decode Method A): seek 후 디코드 끝나면 중간
    // 갭 채워서 다음 재생에 끊김 없도록. ring 모델은 갭 자체가 없음 (head 점프 후
    // 그 위치부터 채움). seek 직후 잠시 무음 가능 (G-2 하이브리드 시작이 ready
    // timeout으로 흡수).
};

OboeEngine& engine() {
    static OboeEngine instance;
    return instance;
}

} // namespace

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeLoadFile(
    JNIEnv* env, jobject /*thiz*/, jstring jPath) {
    const char* path = env->GetStringUTFChars(jPath, nullptr);
    bool ok = engine().loadFile(path);
    env->ReleaseStringUTFChars(jPath, path);
    return ok ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeGetLastError(
    JNIEnv* env, jobject /*thiz*/) {
    return env->NewStringUTF(engine().lastError().c_str());
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativePrewarm(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().prewarm() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeCoolDown(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().coolDown() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeStart(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().start() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeStop(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().stop() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeScheduleStart(
    JNIEnv* /*env*/, jobject /*thiz*/, jlong wallEpochMs, jlong fromFrame) {
    return engine().scheduleStart(
        static_cast<int64_t>(wallEpochMs), static_cast<int64_t>(fromFrame))
        ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeCancelSchedule(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().cancelSchedule() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlongArray JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeGetTimestamp(
    JNIEnv* env, jobject /*thiz*/) {
    int64_t framePos = -1, timeNs = -1, wallNs = -1, vf = 0;
    double outputLatencyMs = -1.0;
    const bool ok = engine().getLatestTimestamp(
        &framePos, &timeNs, &wallNs, &vf, &outputLatencyMs);
    // outputLatencyMs는 micro 단위(long)로 인코딩해 long array에 실음.
    // -1.0 (미지원/측정 불가)은 -1로 보존. Kotlin/Dart에서 ÷1000.0으로 복원.
    const int64_t outLatMicro =
        outputLatencyMs < 0 ? -1
                            : static_cast<int64_t>(outputLatencyMs * 1000.0);
    jlongArray arr = env->NewLongArray(8);
    const jlong vals[8] = {
        framePos, timeNs, wallNs, ok ? 1L : 0L, vf,
        engine().getSampleRate(), engine().getTotalFrames(), outLatMicro
    };
    env->SetLongArrayRegion(arr, 0, 8, vals);
    return arr;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeSeekToFrame(
    JNIEnv* /*env*/, jobject /*thiz*/, jlong newFrame) {
    return engine().seekToFrame(static_cast<int64_t>(newFrame))
        ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeGetVirtualFrame(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return static_cast<jlong>(engine().getVirtualFrame());
}

JNIEXPORT void JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeSetMuted(
    JNIEnv* /*env*/, jobject /*thiz*/, jboolean muted) {
    engine().setMuted(muted == JNI_TRUE);
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeIsMuted(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().isMuted() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeUnload(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().unload() ? JNI_TRUE : JNI_FALSE;
}

}
