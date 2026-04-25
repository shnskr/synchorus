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

        // ---- 버퍼 사전 할당 (silence로 채움) ----
        int64_t estFrames = (durationUs * sampleRate) / 1000000LL;
        int64_t estBytes = estFrames * channelCount * static_cast<int64_t>(sizeof(int16_t));
        if (estBytes > 150LL * 1024 * 1024) {
            int estMinutes = static_cast<int>(durationUs / 60000000LL);
            LOGE("loadFile: too large (%lld MB est, ~%d min)",
                 static_cast<long long>(estBytes / (1024 * 1024)), estMinutes);
            mLastError = "TOO_LONG:" + std::to_string(estMinutes);
            AMediaCodec_stop(codec);
            AMediaCodec_delete(codec);
            AMediaExtractor_delete(extractor);
            return false;
        }

        mDecodedData.assign(
            static_cast<size_t>(estFrames * channelCount), int16_t(0));
        mDecodedBufSize = static_cast<int64_t>(mDecodedData.size());

        // ---- 메타데이터 설정 ----
        mDecodedChannels = channelCount;
        mDecodedSampleRate = sampleRate;
        mDecodedTotalFrames = estFrames;
        mVirtualFrame.store(0, std::memory_order_relaxed);

        // ---- 스트리밍 디코드 상태 초기화 ----
        mDecodeAbort.store(false, std::memory_order_relaxed);
        mDecodeSeekTarget.store(-1, std::memory_order_relaxed);
        mSeqDecodeEnd.store(0, std::memory_order_relaxed);
        mSeekDecodeStart.store(-1, std::memory_order_relaxed);
        mSeekDecodeEnd.store(-1, std::memory_order_relaxed);
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

    bool start() {
        std::lock_guard<std::mutex> lock(mLock);
        if (mStream) {
            LOGI("start: stream already exists, returning true");
            return true;
        }
        if (!mFileLoaded) {
            LOGE("start: no file loaded");
            return false;
        }

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
            LOGE("openStream: %s", oboe::convertToText(result));
            mStream.reset();
            return false;
        }

        mStreamSampleRate = mStream->getSampleRate();
        LOGI("stream OK: reqSR=%d actualSR=%d burst=%d",
             mDecodedSampleRate, mStreamSampleRate,
             mStream->getFramesPerBurst());

        result = mStream->requestStart();
        if (result != oboe::Result::OK) {
            LOGE("requestStart: %s", oboe::convertToText(result));
            mStream->close();
            mStream.reset();
            return false;
        }
        return true;
    }

    bool stop() {
        std::lock_guard<std::mutex> lock(mLock);
        if (!mStream) return true;
        mStream->requestStop();
        mStream->close();
        mStream.reset();
        return true;
    }

    bool unload() {
        stop();
        stopDecodeThread();
        resetState();
        mVirtualFrame.store(0, std::memory_order_relaxed);
        return true;
    }

    bool getLatestTimestamp(
        int64_t* outFramePos,
        int64_t* outTimeNs,
        int64_t* outWallAtFramePosNs,
        int64_t* outVirtualFrame) {

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

        std::lock_guard<std::mutex> lock(mLock);
        if (!mStream) {
            *outFramePos = -1;
            *outTimeNs = -1;
            *outWallAtFramePosNs = wallNow;
            return false;
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

    bool seekToFrame(int64_t newFrame) {
        if (!mFileLoaded) return false;
        int64_t clamped = std::max(
            int64_t(0), std::min(newFrame, mDecodedTotalFrames));
        mVirtualFrame.store(clamped, std::memory_order_relaxed);

        // 미디코딩 영역으로 seek → 디코드 스레드에 점프 요청
        if (mDecoding.load(std::memory_order_relaxed) &&
            !isFrameDecoded(clamped)) {
            mDecodeSeekTarget.store(clamped, std::memory_order_release);
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

        const bool muted = mMuted.load(std::memory_order_relaxed);
        int64_t vf = mVirtualFrame.load(std::memory_order_relaxed);

        // 디코드 범위 캐싱 (acquire: 디코드 스레드의 버퍼 쓰기 가시성 보장)
        const int64_t seqEnd = mSeqDecodeEnd.load(std::memory_order_acquire);
        const int64_t seekStart = mSeekDecodeStart.load(std::memory_order_acquire);
        const int64_t seekEnd = mSeekDecodeEnd.load(std::memory_order_acquire);
        const int64_t totalFrames = mDecodedTotalFrames;

        for (int i = 0; i < numFrames; ++i) {
            const bool decoded =
                (vf >= 0 && vf < seqEnd) ||
                (seekStart >= 0 && vf >= seekStart && vf < seekEnd);

            for (int ch = 0; ch < outCh; ++ch) {
                float sample = 0.0f;
                if (!muted && decoded && vf >= 0 && vf < totalFrames) {
                    int srcCh = std::min(ch, mDecodedChannels - 1);
                    int64_t idx = vf * mDecodedChannels + srcCh;
                    sample = static_cast<float>(mDecodedData[idx]) / 32768.0f;
                }
                *output++ = sample;
            }
            ++vf;
        }

        mVirtualFrame.store(vf, std::memory_order_relaxed);
        return oboe::DataCallbackResult::Continue;
    }

private:
    // ---- 재생 상태 ----
    std::shared_ptr<oboe::AudioStream> mStream;
    int32_t mStreamSampleRate = 48000;
    std::atomic<int64_t> mVirtualFrame{0};
    std::atomic<bool> mMuted{false};
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

    // ---- 디코딩된 오디오 버퍼 ----
    std::vector<int16_t> mDecodedData;
    int64_t mDecodedBufSize = 0;    // mDecodedData.size() 캐시
    int32_t mDecodedChannels = 0;
    int32_t mDecodedSampleRate = 0;
    int64_t mDecodedTotalFrames = 0;
    bool mFileLoaded = false;
    std::string mLastError;

    // ---- 스트리밍 디코드 상태 ----
    std::thread mDecodeThread;
    std::atomic<bool> mDecoding{false};
    std::atomic<bool> mDecodeAbort{false};
    std::atomic<int64_t> mDecodeSeekTarget{-1};

    // 디코드 완료 범위 추적 (2개 범위로 커버)
    // [0, mSeqDecodeEnd): 처음부터 순차 디코드된 영역
    // [mSeekDecodeStart, mSeekDecodeEnd): seek 후 디코드된 영역
    std::atomic<int64_t> mSeqDecodeEnd{0};
    std::atomic<int64_t> mSeekDecodeStart{-1};
    std::atomic<int64_t> mSeekDecodeEnd{-1};

    // 최소 버퍼 대기용
    std::atomic<int64_t> mDecodedFrameCount{0};
    std::mutex mMinBufMutex;
    std::condition_variable mMinBufCv;

    // ---- 헬퍼 ----

    inline bool isFrameDecoded(int64_t frame) const {
        if (frame < mSeqDecodeEnd.load(std::memory_order_acquire)) return true;
        int64_t ss = mSeekDecodeStart.load(std::memory_order_acquire);
        int64_t se = mSeekDecodeEnd.load(std::memory_order_acquire);
        return (ss >= 0 && frame >= ss && frame < se);
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
        mDecodedChannels = 0;
        mDecodedSampleRate = 0;
        mDecodedTotalFrames = 0;
        mFileLoaded = false;
        mLastError.clear();
        mSeqDecodeEnd.store(0, std::memory_order_relaxed);
        mSeekDecodeStart.store(-1, std::memory_order_relaxed);
        mSeekDecodeEnd.store(-1, std::memory_order_relaxed);
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

    // ---- 백그라운드 디코드 메인 루프 ----
    // extractor, codec의 소유권을 받아 정리까지 책임진다.
    void decodeLoop(AMediaExtractor* extractor, AMediaCodec* codec,
                    int channelCount, int32_t sampleRate) {

        int64_t writeFrame = 0;
        int64_t seqEnd = 0;       // 순차 디코드 끝 위치 (로컬 캐시)
        bool inputEos = false;
        bool outputEos = false;
        bool needsPtsReset = false;
        bool inSeekMode = false;   // seek 후 디코드 중인지

        while (!outputEos && !mDecodeAbort.load(std::memory_order_relaxed)) {
            // ---- seek 요청 확인 ----
            int64_t seekTarget = mDecodeSeekTarget.exchange(
                -1, std::memory_order_acquire);
            if (seekTarget >= 0) {
                if (!inSeekMode) {
                    // 순차 디코드 끝 위치 기록
                    seqEnd = writeFrame;
                    mSeqDecodeEnd.store(seqEnd, std::memory_order_release);
                }

                LOGI("decode: seek to frame %lld (seqEnd=%lld)",
                     static_cast<long long>(seekTarget),
                     static_cast<long long>(seqEnd));

                AMediaCodec_flush(codec);
                int64_t seekUs =
                    (seekTarget * 1000000LL) / sampleRate;
                AMediaExtractor_seekTo(
                    extractor, seekUs,
                    AMEDIAEXTRACTOR_SEEK_CLOSEST_SYNC);

                inputEos = false;
                outputEos = false;
                needsPtsReset = true;
                inSeekMode = true;
                writeFrame = seekTarget; // PTS로 보정 예정
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

            // ---- 출력 단계: codec → PCM 버퍼 ----
            AMediaCodecBufferInfo info;
            ssize_t outIdx = AMediaCodec_dequeueOutputBuffer(codec, &info, 10000);

            if (outIdx >= 0) {
                if (info.size > 0) {
                    // seek 직후 첫 출력: PTS로 정확한 쓰기 위치 설정
                    if (needsPtsReset && info.presentationTimeUs >= 0) {
                        int64_t ptsFrame =
                            (info.presentationTimeUs * sampleRate) / 1000000LL;
                        writeFrame = ptsFrame;
                        mSeekDecodeStart.store(
                            ptsFrame, std::memory_order_release);
                        mSeekDecodeEnd.store(
                            ptsFrame, std::memory_order_release);
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

                    // 사전 할당 버퍼에 쓰기 (범위 체크)
                    int64_t writeStart = writeFrame * channelCount;
                    int64_t writeEnd = writeStart + numSamples;
                    if (writeStart >= 0 && writeEnd <= mDecodedBufSize) {
                        std::copy(samples, samples + numSamples,
                                  mDecodedData.data() + writeStart);
                    } else if (writeStart >= 0 && writeStart < mDecodedBufSize) {
                        // 부분 쓰기 (버퍼 끝 초과분 잘림)
                        int64_t safeSamples = mDecodedBufSize - writeStart;
                        std::copy(samples, samples + safeSamples,
                                  mDecodedData.data() + writeStart);
                    }

                    writeFrame += numFrames;

                    // 디코드 범위 갱신
                    if (inSeekMode) {
                        mSeekDecodeEnd.store(
                            writeFrame, std::memory_order_release);
                    } else {
                        seqEnd = writeFrame;
                        mSeqDecodeEnd.store(
                            seqEnd, std::memory_order_release);
                    }

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

        // ---- 갭 채우기 (Method A) ----
        if (!mDecodeAbort.load(std::memory_order_relaxed) && inSeekMode) {
            fillGaps(extractor, codec, channelCount, sampleRate, seqEnd);
        }

        // ---- 전체 디코드 완료 표시 ----
        if (!mDecodeAbort.load(std::memory_order_relaxed)) {
            mSeqDecodeEnd.store(
                mDecodedTotalFrames, std::memory_order_release);
            mSeekDecodeStart.store(-1, std::memory_order_release);
            mSeekDecodeEnd.store(-1, std::memory_order_release);

            // 실제 디코딩된 프레임으로 보정
            if (writeFrame > 0 && writeFrame != mDecodedTotalFrames) {
                LOGI("decode: actual frames %lld vs est %lld",
                     static_cast<long long>(writeFrame),
                     static_cast<long long>(mDecodedTotalFrames));
                // est보다 적으면 보정 (초과는 무시 — 이미 버퍼 범위 체크됨)
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

    // ---- 갭 채우기: [gapStart, seekStart) 구간 디코딩 ----
    void fillGaps(AMediaExtractor* extractor, AMediaCodec* codec,
                  int channelCount, int32_t sampleRate,
                  int64_t gapStart) {

        int64_t gapEnd = mSeekDecodeStart.load(std::memory_order_relaxed);
        if (gapEnd < 0 || gapStart >= gapEnd) {
            LOGI("fillGaps: no gap (seqEnd=%lld, seekStart=%lld)",
                 static_cast<long long>(gapStart),
                 static_cast<long long>(gapEnd));
            return;
        }

        LOGI("fillGaps: frames %lld to %lld",
             static_cast<long long>(gapStart),
             static_cast<long long>(gapEnd));

        AMediaCodec_flush(codec);
        int64_t seekUs = (gapStart * 1000000LL) / sampleRate;
        AMediaExtractor_seekTo(
            extractor, seekUs, AMEDIAEXTRACTOR_SEEK_CLOSEST_SYNC);

        int64_t writeFrame = gapStart;
        bool needsPtsReset = true;
        bool inputEos = false;
        bool outputEos = false;

        while (!outputEos && !mDecodeAbort.load(std::memory_order_relaxed)) {
            // 입력 단계
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

            // 출력 단계
            AMediaCodecBufferInfo info;
            ssize_t outIdx = AMediaCodec_dequeueOutputBuffer(codec, &info, 10000);

            if (outIdx >= 0) {
                if (info.size > 0) {
                    if (needsPtsReset && info.presentationTimeUs >= 0) {
                        writeFrame =
                            (info.presentationTimeUs * sampleRate) / 1000000LL;
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

                    // 버퍼에 쓰기
                    int64_t writeStart = writeFrame * channelCount;
                    int64_t writeEnd = writeStart + numSamples;
                    if (writeStart >= 0 && writeEnd <= mDecodedBufSize) {
                        std::copy(samples, samples + numSamples,
                                  mDecodedData.data() + writeStart);
                    } else if (writeStart >= 0 && writeStart < mDecodedBufSize) {
                        int64_t safeSamples = mDecodedBufSize - writeStart;
                        std::copy(samples, samples + safeSamples,
                                  mDecodedData.data() + writeStart);
                    }

                    writeFrame += numFrames;

                    // 순차 디코드 범위 확장
                    mSeqDecodeEnd.store(
                        writeFrame, std::memory_order_release);
                }

                if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) {
                    outputEos = true;
                }
                AMediaCodec_releaseOutputBuffer(
                    codec, static_cast<size_t>(outIdx), false);

            } else if (outIdx == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
                AMediaFormat* newFmt = AMediaCodec_getOutputFormat(codec);
                AMediaFormat_delete(newFmt);
            }

            // 갭 끝을 넘었으면 종료
            if (writeFrame >= gapEnd) break;
        }

        LOGI("fillGaps: done, wrote up to frame %lld",
             static_cast<long long>(writeFrame));
    }
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
Java_com_synchorus_synchorus_NativeAudio_nativeStart(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().start() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeStop(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().stop() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlongArray JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeGetTimestamp(
    JNIEnv* env, jobject /*thiz*/) {
    int64_t framePos = -1, timeNs = -1, wallNs = -1, vf = 0;
    const bool ok = engine().getLatestTimestamp(
        &framePos, &timeNs, &wallNs, &vf);
    jlongArray arr = env->NewLongArray(7);
    const jlong vals[7] = {
        framePos, timeNs, wallNs, ok ? 1L : 0L, vf,
        engine().getSampleRate(), engine().getTotalFrames()
    };
    env->SetLongArrayRegion(arr, 0, 7, vals);
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
