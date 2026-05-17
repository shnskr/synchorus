// PoC Phase 0~4: Oboe 래퍼 + sine wave 재생 + virtual playhead seek
//
// Phase 4: 게스트가 호스트와 드리프트 나면 seek로 보정하는 실험 수단.
//   - sine wave는 internal 프레임 카운터(mVirtualFrame) 기반으로 생성.
//     mVirtualFrame = "콜백이 다음에 만들 첫 프레임의 절대 번호".
//   - seekToFrame(N) → mVirtualFrame = N 으로 덮어씀. 다음 콜백부터 새 위치의
//     sine 생성. 단, Oboe HAL 버퍼에 이미 들어간 프레임은 그대로 재생됨 →
//     Oboe getTimestamp가 이 변화를 몇 ms 안에 반영하는지가 Phase 4 측정 포인트.
//   - getTimestamp는 그대로 Oboe HAL에서 오는 (framePos=DAC로 나간 프레임 수,
//     timeNs=그 순간의 CLOCK_MONOTONIC) 반환. getVirtualFrame은 내부 카운터
//     스냅샷 반환. 두 값 차이 ≈ HAL 버퍼 레이턴시.
//
// §G G-1 RingBufferEngine (2026-05-17): 본 앱 v0.0.76 ring buffer race 격리
// 검증용 별도 엔진. 기존 OboeEngine과 독립. mp3 디코더는 sine wave generator로
// 대체 (race 원인은 디코더가 아니라 ring buffer 동기화). 파일 끝 RingBufferEngine
// 클래스 + JNI 참조.

#include <oboe/Oboe.h>
#include <jni.h>
#include <android/log.h>
#include <time.h>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

#define LOG_TAG "OboeEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

constexpr float kAmplitude = 0.3f;
// C major 음계 (도레미파솔라시도). 1초마다 다음 음으로 순환.
// 싱크 맞으면 같은 음, 1초 어긋나면 다른 음이 들림 → 청각 검증 용이.
constexpr float kNoteFrequencies[] = {
    261.63f,  // C4 (도)
    293.66f,  // D4 (레)
    329.63f,  // E4 (미)
    349.23f,  // F4 (파)
    392.00f,  // G4 (솔)
    440.00f,  // A4 (라)
    493.88f,  // B4 (시)
    523.25f,  // C5 (도)
};
constexpr int kNumNotes = sizeof(kNoteFrequencies) / sizeof(kNoteFrequencies[0]);
// 1초 주기 비프음 파라미터. 귀로 에코/지연을 체감하기 위함.
// period = 1s, beep = 100ms, 나머지 900ms 무음. 비프 시작/끝 5ms fade로
// 클릭음 방지. 모두 sampleRate 기반이라 실제 스트림 rate 따라감.
constexpr float kBeepPeriodSec = 1.0f;
constexpr float kBeepDurationSec = 0.1f;
constexpr float kBeepFadeSec = 0.005f;

class OboeEngine : public oboe::AudioStreamDataCallback {
public:
    bool start() {
        std::lock_guard<std::mutex> lock(mLock);
        if (mStream) {
            LOGI("start: already running");
            return true;
        }

        oboe::AudioStreamBuilder builder;
        oboe::Result result = builder
            .setDirection(oboe::Direction::Output)
            ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
            ->setSharingMode(oboe::SharingMode::Exclusive)
            ->setFormat(oboe::AudioFormat::Float)
            ->setChannelCount(oboe::ChannelCount::Stereo)
            ->setDataCallback(this)
            ->openStream(mStream);
        if (result != oboe::Result::OK) {
            LOGE("openStream failed: %s", oboe::convertToText(result));
            mStream.reset();
            return false;
        }

        mVirtualFrame.store(0, std::memory_order_relaxed);
        mSampleRate = mStream->getSampleRate();
        LOGI("openStream OK: sampleRate=%d framesPerBurst=%d",
             mSampleRate, mStream->getFramesPerBurst());

        result = mStream->requestStart();
        if (result != oboe::Result::OK) {
            LOGE("requestStart failed: %s", oboe::convertToText(result));
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

    // Phase 1: Flutter 측 100ms 주기 폴링용.
    // 반환 false = 스트림 미시작 / HAL이 아직 timestamp 제공 불가 상태.
    //
    // Phase 5 추가: outWallAtFramePosNs.
    // Oboe getTimestamp는 (framePos, timeNs_mono)를 주는데 timeNs_mono는
    // "framePos가 DAC에 나간 과거 순간"의 CLOCK_MONOTONIC. Dart 쪽에서
    // DateTime.now()를 네이티브 호출 이전에 찍어 쓰면 wall/mono 캡처 순간이 달라져
    // 샘플마다 편차(최대 40ms)가 생김 → 게스트 외삽에서 ±100ms 스파이크 발생.
    //
    // 해결: 네이티브 내부에서 getTimestamp 직후 CLOCK_MONOTONIC과 CLOCK_REALTIME을
    // 같이 찍어서 (mono_now, wall_now)를 얻고, (wall_now - (mono_now - timeNs_mono))
    // = "framePos가 DAC에 나갔던 순간의 CLOCK_REALTIME 추정치" = outWallAtFramePosNs.
    // 이 값은 framePos와 atomically 정합이므로 샘플 간 rate가 일정.
    bool getLatestTimestamp(
        int64_t* outFramePos,
        int64_t* outTimeNs,
        int64_t* outWallAtFramePosNs,
        int64_t* outVirtualFrame) {
        std::lock_guard<std::mutex> lock(mLock);
        if (!mStream) {
            *outFramePos = -1;
            *outTimeNs = -1;
            *outWallAtFramePosNs = -1;
            *outVirtualFrame = 0;
            return false;
        }
        int64_t framePos = 0;
        int64_t timeNs = 0;
        oboe::Result result = mStream->getTimestamp(CLOCK_MONOTONIC, &framePos, &timeNs);
        if (result != oboe::Result::OK) {
            *outFramePos = -1;
            *outTimeNs = -1;
            *outWallAtFramePosNs = -1;
            *outVirtualFrame = 0;
            return false;
        }
        // getTimestamp 바로 직후 두 시계를 같이 찍음. 이 두 타임스탬프 사이 간격은
        // 수 ns이므로 "같은 순간"으로 취급해도 무방.
        struct timespec wallTs;
        struct timespec monoTs;
        clock_gettime(CLOCK_REALTIME, &wallTs);
        clock_gettime(CLOCK_MONOTONIC, &monoTs);
        const int64_t wallNow =
            static_cast<int64_t>(wallTs.tv_sec) * 1000000000LL + wallTs.tv_nsec;
        const int64_t monoNow =
            static_cast<int64_t>(monoTs.tv_sec) * 1000000000LL + monoTs.tv_nsec;
        // timeNs는 과거. gap = "지금까지 얼마나 지났나".
        const int64_t gap = monoNow - timeNs;
        *outFramePos = framePos;
        *outTimeNs = timeNs;
        *outWallAtFramePosNs = wallNow - gap;
        // 같은 lock 안에서 virtualFrame도 읽어서 wallMs와 원자적으로 묶음.
        *outVirtualFrame = mVirtualFrame.load(std::memory_order_relaxed);
        return true;
    }

    // Phase 4: "내가 다음에 만들 프레임 번호" (virtual playhead).
    // Oboe framePos와 차이 = HAL 버퍼 레이턴시.
    int64_t getVirtualFrame() const {
        return mVirtualFrame.load(std::memory_order_relaxed);
    }

    // Phase 4: seek. mVirtualFrame을 newFrame으로 덮어씀. 다음 콜백부터
    // 새 위치 sine 생성. 주의: HAL 버퍼에 이미 들어간 프레임(수 ms)은 여전히
    // 이전 위치로 재생됨. 이 지연이 실제 오디오에 반영되는 시점은 getTimestamp로
    // 관찰해야 함.
    bool seekToFrame(int64_t newFrame) {
        std::lock_guard<std::mutex> lock(mLock);
        if (!mStream) return false;
        mVirtualFrame.store(newFrame, std::memory_order_relaxed);
        return true;
    }

    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* stream,
        void* audioData,
        int32_t numFrames) override {
        auto* output = static_cast<float*>(audioData);
        const int channelCount = stream->getChannelCount();
        const double sr = static_cast<double>(mSampleRate);
        // 비프 파라미터 → frame 단위 변환. sampleRate 기반이라 스트림 rate 변경에
        // 자동 적응.
        const int64_t beepPeriodFrames =
            static_cast<int64_t>(static_cast<double>(kBeepPeriodSec) * sr);
        const int64_t beepDurationFrames =
            static_cast<int64_t>(static_cast<double>(kBeepDurationSec) * sr);
        const int64_t beepFadeFrames =
            static_cast<int64_t>(static_cast<double>(kBeepFadeSec) * sr);
        // relaxed fetch → 이번 콜백 시작 시점의 virtual frame 스냅샷
        int64_t vf = mVirtualFrame.load(std::memory_order_relaxed);
        for (int i = 0; i < numFrames; ++i) {
            // vf가 seek로 음수일 수 있어 양의 modulo 계산.
            // mod = 현재 프레임이 1초 주기 내에서 몇 번째 프레임인지.
            int64_t mod = vf % beepPeriodFrames;
            if (mod < 0) mod += beepPeriodFrames;

            float sample = 0.0f;
            if (mod < beepDurationFrames) {
                // 몇 번째 비트인지 → 음계 선택 (도레미파솔라시도 순환).
                // (vf - mod)은 현재 주기의 시작점, 나누면 beat index.
                const int64_t beatIndex = (vf - mod) / beepPeriodFrames;
                const int noteIdx = static_cast<int>(
                    ((beatIndex % kNumNotes) + kNumNotes) % kNumNotes);
                const double freq = static_cast<double>(kNoteFrequencies[noteIdx]);
                // mod 기준 phase → 매 비프가 phase 0에서 시작 (클릭 방지).
                const double phase = 2.0 * M_PI * freq
                    * static_cast<double>(mod) / sr;
                float env = 1.0f;
                if (mod < beepFadeFrames) {
                    // fade-in: 0 → 1
                    env = static_cast<float>(mod)
                        / static_cast<float>(beepFadeFrames);
                } else if (mod >= beepDurationFrames - beepFadeFrames) {
                    // fade-out: 1 → 0
                    const int64_t remaining = beepDurationFrames - mod;
                    env = static_cast<float>(remaining)
                        / static_cast<float>(beepFadeFrames);
                }
                sample = static_cast<float>(std::sin(phase)) * kAmplitude * env;
            }
            // 나머지는 무음 (sample = 0)
            for (int ch = 0; ch < channelCount; ++ch) {
                *output++ = sample;
            }
            ++vf;
        }
        // store 시점과 다른 스레드의 seek 사이 race는 허용 (짧게 한 콜백만 덮어씀).
        mVirtualFrame.store(vf, std::memory_order_relaxed);
        return oboe::DataCallbackResult::Continue;
    }

private:
    std::shared_ptr<oboe::AudioStream> mStream;
    int32_t mSampleRate = 48000;
    // Phase 4: seek 타깃. 콜백과 seek 요청이 서로 다른 스레드에서 접근하므로 atomic.
    std::atomic<int64_t> mVirtualFrame{0};
    std::mutex mLock;
};

OboeEngine& engine() {
    static OboeEngine instance;
    return instance;
}

} // namespace

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeStart(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().start() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeStop(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().stop() ? JNI_TRUE : JNI_FALSE;
}

// Phase 1: Flutter가 100ms 주기로 polling.
// 반환 배열: [framePos, timeNs, wallAtFramePosNs, ok(1|0), virtualFrame]
// wallAtFramePosNs는 "framePos가 DAC에 나간 순간의 CLOCK_REALTIME (ns)".
// virtualFrame은 같은 lock 안에서 읽은 mVirtualFrame — wallMs와 원자적 정합.
JNIEXPORT jlongArray JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeGetTimestamp(
    JNIEnv* env, jobject /*thiz*/) {
    int64_t framePos = -1;
    int64_t timeNs = -1;
    int64_t wallAtFramePosNs = -1;
    int64_t virtualFrame = 0;
    const bool ok = engine().getLatestTimestamp(
        &framePos, &timeNs, &wallAtFramePosNs, &virtualFrame);
    jlongArray arr = env->NewLongArray(5);
    const jlong values[5] = {
        framePos, timeNs, wallAtFramePosNs, ok ? 1L : 0L, virtualFrame
    };
    env->SetLongArrayRegion(arr, 0, 5, values);
    return arr;
}

// Phase 4: virtual playhead seek. 성공 시 true.
JNIEXPORT jboolean JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeSeekToFrame(
    JNIEnv* /*env*/, jobject /*thiz*/, jlong newFrame) {
    return engine().seekToFrame(static_cast<int64_t>(newFrame)) ? JNI_TRUE : JNI_FALSE;
}

// Phase 4: 현재 virtual playhead 값. 스트림 미시작 시 -1 대신 0 반환해도 무방.
JNIEXPORT jlong JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeGetVirtualFrame(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return static_cast<jlong>(engine().getVirtualFrame());
}

}

// ============================================================================
// §G G-1 RingBufferEngine: 본 앱 v0.0.76 ring buffer race 격리 검증용
// ============================================================================
//
// 본 앱 commit f7e4dfa(v0.0.76)의 ring buffer 구조를 mp3 디코더 빼고 sine wave
// generator로 옮긴 것. race 시나리오를 PoC 환경에서 재현하기 위함.
//
// v0.0.76 race (HISTORY (95) 확정):
//   외부 thread A: seekToFrame(target1) → head/tail/seekTarget 3 atomic store + notify
//   외부 thread B: 0.3초 후 seekToFrame(target2) → 3 atomic store + notify (연타)
//   decodeLoop:    깨어남, seekTarget.exchange → 처리 도중 외부 write 또 들어옴
//   결과: head/tail invariant 깨짐 → isFrameDecoded(vf) 영구 false → 무음
//
// 큐 모델 fix는 step 6 (PoC ring buffer를 큐 모델로 재설계)에서 적용.
// 현 코드는 race 있는 v0.0.76 그대로.

namespace ringpoc {

constexpr int kRingSampleRate = 48000;
constexpr int kRingChannels = 2;
constexpr int kRingSeconds = 60;
constexpr int kRingBehindSeconds = 10;
constexpr int kRingAheadSeconds = 50;
static_assert(kRingBehindSeconds + kRingAheadSeconds == kRingSeconds, "ring 분배");

// Sine generator: 도레미파솔라시도 1초 주기 (기존 PoC와 동일 패턴).
// chunk = 4096 frame → 재생 분량 ~85ms/chunk. 디코더 sleep 40ms → 디코더가
// 재생보다 ~2배 빠름 (ring buffer 자연 채움). race window = 40ms (chunk decode
// wall time)로 자동 test 50ms 주기에 첫 chunk 처리 중 두 번째 seek 도착 가능.
// chunk 1024 + sleep 40ms로 했더니 디코더가 realtime의 0.53배 속도라 vf > ringHead
// 영구 starvation (1차 시도 fail).
constexpr int kRingChunkFrames = 4096;
constexpr int kRingDecodeChunkSleepUs = 40000;
// 가상 곡 길이 (RingBufferEngine 시작 시 설정). 30분 정도.
constexpr int64_t kRingTotalFrames =
    static_cast<int64_t>(kRingSampleRate) * 60 * 30;

constexpr float kRingAmplitude = 0.3f;
constexpr float kRingNotes[] = {
    261.63f, 293.66f, 329.63f, 349.23f,
    392.00f, 440.00f, 493.88f, 523.25f,
};
constexpr int kRingNumNotes = sizeof(kRingNotes) / sizeof(kRingNotes[0]);
constexpr float kRingBeepPeriodSec = 1.0f;
constexpr float kRingBeepDurationSec = 0.1f;
constexpr float kRingBeepFadeSec = 0.005f;

class RingBufferEngine : public oboe::AudioStreamDataCallback {
public:
    ~RingBufferEngine() {
        stop();
    }

    // 시작: stream open + decoder thread 시작.
    bool start() {
        std::lock_guard<std::mutex> lock(mLock);
        if (mStream) {
            return true;
        }

        // ring buffer 사전 할당 (60s × 48k × 2ch × int16 ≈ 11.5MB)
        mRingCapacityFrames = static_cast<int64_t>(kRingSampleRate) * kRingSeconds;
        const int64_t samples = mRingCapacityFrames * kRingChannels;
        mDecodedData.assign(static_cast<size_t>(samples), int16_t(0));

        mVirtualFrame.store(0, std::memory_order_relaxed);
        mRingHead.store(0, std::memory_order_relaxed);
        mRingTail.store(0, std::memory_order_relaxed);
        mDecodeSeekTarget.store(-1, std::memory_order_relaxed);
        mDecodeAbort.store(false, std::memory_order_relaxed);
        mPcmReadSilentCount.store(0, std::memory_order_relaxed);
        mPcmReadDecodedCount.store(0, std::memory_order_relaxed);
        mSeekCallCount.store(0, std::memory_order_relaxed);

        // ---- Oboe stream open ----
        oboe::AudioStreamBuilder builder;
        oboe::Result result = builder
            .setDirection(oboe::Direction::Output)
            ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
            ->setSharingMode(oboe::SharingMode::Exclusive)
            ->setFormat(oboe::AudioFormat::Float)
            ->setChannelCount(oboe::ChannelCount::Stereo)
            ->setSampleRate(kRingSampleRate)
            ->setDataCallback(this)
            ->openStream(mStream);
        if (result != oboe::Result::OK) {
            LOGE("Ring start openStream: %s", oboe::convertToText(result));
            mStream.reset();
            return false;
        }
        mStreamSampleRate = mStream->getSampleRate();

        // ---- decoder thread 시작 ----
        mDecoding.store(true, std::memory_order_release);
        mDecodeThread = std::thread(&RingBufferEngine::decodeLoop, this);

        // ---- 최소 1초 분량 채워질 때까지 wait ----
        {
            std::unique_lock<std::mutex> lk(mMinBufMutex);
            mMinBufCv.wait_for(lk, std::chrono::seconds(3), [&] {
                return mRingHead.load(std::memory_order_relaxed) >= kRingSampleRate
                    || mDecodeAbort.load(std::memory_order_relaxed);
            });
        }

        result = mStream->requestStart();
        if (result != oboe::Result::OK) {
            LOGE("Ring start requestStart: %s", oboe::convertToText(result));
            mStream->close();
            mStream.reset();
            stopDecodeThread();
            return false;
        }
        LOGI("Ring start OK: sr=%d cap=%lld", mStreamSampleRate,
             static_cast<long long>(mRingCapacityFrames));
        return true;
    }

    bool stop() {
        stopDecodeThread();
        std::lock_guard<std::mutex> lock(mLock);
        if (mStream) {
            mStream->requestStop();
            mStream->close();
            mStream.reset();
        }
        mDecodedData.clear();
        mDecodedData.shrink_to_fit();
        return true;
    }

    // 큐 모델 fix (2026-05-17): 외부는 mPendingSeekTarget만 set, ring head/tail은
    // decodeLoop 단일 thread에서만 갱신. v0.0.76 race의 root cause인 "외부 thread와
    // decodeLoop이 동시에 ring head/tail 갱신" 자체를 차단.
    //
    // 기존 race 코드 (v0.0.76, 위에 history): seekToFrame에서 직접 ring head/tail
    // store + seekTarget set. 연타 시 invariant 깨짐.
    //
    // mUseQueueFix = false 일 때만 race 모델로 폴백 (비교 측정용, 기본 false면 fix 활성).
    bool seekToFrame(int64_t newFrame) {
        if (!mDecoding.load(std::memory_order_relaxed)) return false;
        int64_t clamped = std::max(int64_t(0), std::min(newFrame, kRingTotalFrames));
        mVirtualFrame.store(clamped, std::memory_order_relaxed);
        mSeekCallCount.fetch_add(1, std::memory_order_relaxed);

        // 윈도우 안 = 즉시 (작은 seek). 밖 = decode 점프 요청만 보냄.
        if (!isFrameDecoded(clamped)) {
            if (mUseQueueFix.load(std::memory_order_relaxed)) {
                // FIX: ring head/tail 안 건드림, decodeLoop이 처리.
                mDecodeSeekTarget.store(clamped, std::memory_order_release);
                std::lock_guard<std::mutex> lk(mRingMutex);
                mRingCv.notify_all();
            } else {
                // RACE (v0.0.76 baseline): 외부에서 직접 갱신.
                mRingHead.store(clamped, std::memory_order_release);   // (a)
                mRingTail.store(clamped, std::memory_order_release);   // (b)
                mDecodeSeekTarget.store(clamped, std::memory_order_release); // (c)
                std::lock_guard<std::mutex> lk(mRingMutex);
                mRingCv.notify_all();
            }
        }
        return true;
    }

    void setQueueFix(bool enabled) {
        mUseQueueFix.store(enabled, std::memory_order_relaxed);
        LOGI("Ring setQueueFix: %s", enabled ? "ON" : "OFF");
    }

    bool getQueueFix() const {
        return mUseQueueFix.load(std::memory_order_relaxed);
    }

    // 진단용 stats. Dart 폴링.
    void getStats(int64_t* outVf, int64_t* outRingHead, int64_t* outRingTail,
                  int64_t* outSilent, int64_t* outDecoded, int64_t* outSeekCount) {
        *outVf = mVirtualFrame.load(std::memory_order_relaxed);
        *outRingHead = mRingHead.load(std::memory_order_relaxed);
        *outRingTail = mRingTail.load(std::memory_order_relaxed);
        *outSilent = mPcmReadSilentCount.load(std::memory_order_relaxed);
        *outDecoded = mPcmReadDecodedCount.load(std::memory_order_relaxed);
        *outSeekCount = mSeekCallCount.load(std::memory_order_relaxed);
    }

    // v0.0.76 onAudioReady와 동일 — ring buffer 안이면 modular read, 밖이면 무음.
    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* stream,
        void* audioData,
        int32_t numFrames) override {
        auto* output = static_cast<float*>(audioData);
        const int outCh = stream->getChannelCount();

        int64_t vf = mVirtualFrame.load(std::memory_order_relaxed);
        const int64_t ringHead = mRingHead.load(std::memory_order_acquire);
        const int64_t ringTail = mRingTail.load(std::memory_order_acquire);
        const int64_t capFrames = mRingCapacityFrames;
        const int64_t totalFrames = kRingTotalFrames;

        int64_t silentInThisCallback = 0;
        int64_t decodedInThisCallback = 0;
        for (int i = 0; i < numFrames; ++i) {
            const bool decoded = vf >= ringTail && vf < ringHead;
            if (decoded) ++decodedInThisCallback;
            else ++silentInThisCallback;

            for (int ch = 0; ch < outCh; ++ch) {
                float sample = 0.0f;
                if (decoded && vf >= 0 && vf < totalFrames && capFrames > 0) {
                    int srcCh = std::min(ch, kRingChannels - 1);
                    int64_t bufFrame = vf % capFrames;
                    int64_t idx = bufFrame * kRingChannels + srcCh;
                    sample = static_cast<float>(mDecodedData[idx]) / 32768.0f;
                }
                *output++ = sample;
            }
            ++vf;
        }
        mVirtualFrame.store(vf, std::memory_order_relaxed);

        mPcmReadSilentCount.fetch_add(silentInThisCallback, std::memory_order_relaxed);
        mPcmReadDecodedCount.fetch_add(decodedInThisCallback, std::memory_order_relaxed);

        // tail advance (v0.0.76 동일): behind 한도 유지. atomic 갱신.
        if (capFrames > 0) {
            const int64_t behindFrames =
                static_cast<int64_t>(kRingSampleRate) * kRingBehindSeconds;
            const int64_t newTail = std::max<int64_t>(0, vf - behindFrames);
            if (newTail > ringTail) {
                mRingTail.store(newTail, std::memory_order_release);
            }
        }
        return oboe::DataCallbackResult::Continue;
    }

private:
    inline bool isFrameDecoded(int64_t frame) const {
        const int64_t tail = mRingTail.load(std::memory_order_acquire);
        const int64_t head = mRingHead.load(std::memory_order_acquire);
        return frame >= tail && frame < head;
    }

    void stopDecodeThread() {
        mDecodeAbort.store(true, std::memory_order_relaxed);
        {
            std::lock_guard<std::mutex> lk(mRingMutex);
            mRingCv.notify_all();
        }
        {
            std::lock_guard<std::mutex> lk(mMinBufMutex);
            mMinBufCv.notify_all();
        }
        if (mDecodeThread.joinable()) {
            mDecodeThread.join();
        }
        mDecoding.store(false, std::memory_order_relaxed);
    }

    // v0.0.76 decodeLoop: ring 가득 차면 wait, seek 요청 처리, sine chunk write.
    void decodeLoop() {
        int64_t writeFrame = 0;
        while (!mDecodeAbort.load(std::memory_order_relaxed)) {
            // ---- seek 요청 확인 (exchange로 한 번에 가져옴) ----
            int64_t seekTarget = mDecodeSeekTarget.exchange(
                -1, std::memory_order_acquire);
            if (seekTarget >= 0) {
                // FIX 모드: ring head/tail을 여기서 단일 thread로 갱신.
                // RACE 모드 (v0.0.76): seekToFrame()에서 이미 set됨, 여기선 writeFrame만 갱신.
                if (mUseQueueFix.load(std::memory_order_relaxed)) {
                    mRingHead.store(seekTarget, std::memory_order_release);
                    mRingTail.store(seekTarget, std::memory_order_release);
                }
                writeFrame = seekTarget;
                LOGI("Ring decode [%s]: seek to frame %lld",
                     mUseQueueFix.load() ? "FIX" : "RACE",
                     static_cast<long long>(seekTarget));
            }

            // ---- ring 가득 차면 wait ----
            {
                std::unique_lock<std::mutex> lk(mRingMutex);
                mRingCv.wait_for(lk, std::chrono::milliseconds(50), [&] {
                    if (mDecodeAbort.load(std::memory_order_relaxed)) return true;
                    if (mDecodeSeekTarget.load(std::memory_order_relaxed) >= 0)
                        return true;
                    const int64_t head = mRingHead.load(std::memory_order_relaxed);
                    const int64_t tail = mRingTail.load(std::memory_order_relaxed);
                    return (head - tail) < mRingCapacityFrames;
                });
                if (mDecodeAbort.load(std::memory_order_relaxed)) break;
                if (mDecodeSeekTarget.load(std::memory_order_relaxed) >= 0)
                    continue;
            }

            // ---- sine chunk generate + write (mp3 디코더 흉내) ----
            std::this_thread::sleep_for(
                std::chrono::microseconds(kRingDecodeChunkSleepUs));

            const int64_t numFrames = kRingChunkFrames;
            const int64_t capFrames = mRingCapacityFrames;
            const int64_t startBufFrame = writeFrame % capFrames;
            const int64_t framesToBufEnd = capFrames - startBufFrame;

            std::vector<int16_t> chunk(numFrames * kRingChannels);
            for (int64_t i = 0; i < numFrames; ++i) {
                int64_t cf = writeFrame + i;
                // 도레미파솔라시도 1초 주기 sine
                const int64_t beepPeriodFrames =
                    static_cast<int64_t>(kRingBeepPeriodSec * kRingSampleRate);
                const int64_t beepDurationFrames =
                    static_cast<int64_t>(kRingBeepDurationSec * kRingSampleRate);
                const int64_t beepFadeFrames =
                    static_cast<int64_t>(kRingBeepFadeSec * kRingSampleRate);
                int64_t mod = cf % beepPeriodFrames;
                if (mod < 0) mod += beepPeriodFrames;
                int16_t sample = 0;
                if (mod < beepDurationFrames) {
                    const int64_t beatIndex = (cf - mod) / beepPeriodFrames;
                    const int noteIdx = static_cast<int>(
                        ((beatIndex % kRingNumNotes) + kRingNumNotes) % kRingNumNotes);
                    const double freq = static_cast<double>(kRingNotes[noteIdx]);
                    const double phase = 2.0 * M_PI * freq
                        * static_cast<double>(mod) / kRingSampleRate;
                    float env = 1.0f;
                    if (mod < beepFadeFrames) {
                        env = static_cast<float>(mod)
                            / static_cast<float>(beepFadeFrames);
                    } else if (mod >= beepDurationFrames - beepFadeFrames) {
                        const int64_t remaining = beepDurationFrames - mod;
                        env = static_cast<float>(remaining)
                            / static_cast<float>(beepFadeFrames);
                    }
                    const float v = static_cast<float>(std::sin(phase)) * kRingAmplitude * env;
                    sample = static_cast<int16_t>(v * 32767.0f);
                }
                chunk[i * kRingChannels + 0] = sample;
                chunk[i * kRingChannels + 1] = sample;
            }

            // ring write (modular index, wrap-around 시 분할) — v0.0.76 동일
            if (numFrames <= framesToBufEnd) {
                std::copy(chunk.begin(), chunk.end(),
                          mDecodedData.data() + startBufFrame * kRingChannels);
            } else {
                const int64_t firstSamples = framesToBufEnd * kRingChannels;
                std::copy(chunk.begin(), chunk.begin() + firstSamples,
                          mDecodedData.data() + startBufFrame * kRingChannels);
                std::copy(chunk.begin() + firstSamples, chunk.end(),
                          mDecodedData.data());
            }
            writeFrame += numFrames;
            mRingHead.store(writeFrame, std::memory_order_release);

            // 최소 버퍼 대기 해제
            {
                std::lock_guard<std::mutex> lk(mMinBufMutex);
                mMinBufCv.notify_one();
            }

            if (writeFrame >= kRingTotalFrames) break;
        }
        mDecoding.store(false, std::memory_order_release);
        LOGI("Ring decode thread done: writeFrame=%lld",
             static_cast<long long>(writeFrame));
    }

    std::shared_ptr<oboe::AudioStream> mStream;
    int32_t mStreamSampleRate = 0;
    std::mutex mLock;

    std::vector<int16_t> mDecodedData;
    int64_t mRingCapacityFrames = 0;

    std::atomic<int64_t> mVirtualFrame{0};
    std::atomic<int64_t> mRingHead{0};
    std::atomic<int64_t> mRingTail{0};
    std::atomic<int64_t> mDecodeSeekTarget{-1};

    std::thread mDecodeThread;
    std::atomic<bool> mDecoding{false};
    std::atomic<bool> mDecodeAbort{false};

    std::mutex mRingMutex;
    std::condition_variable mRingCv;
    std::mutex mMinBufMutex;
    std::condition_variable mMinBufCv;

    // 진단: PCM read마다 silent/decoded 누적. Dart 폴링.
    std::atomic<int64_t> mPcmReadSilentCount{0};
    std::atomic<int64_t> mPcmReadDecodedCount{0};
    std::atomic<int64_t> mSeekCallCount{0};

    // race 모델 vs 큐 모델 fix 토글. 기본 fix=true.
    std::atomic<bool> mUseQueueFix{true};
};

RingBufferEngine& ringEngine() {
    static RingBufferEngine instance;
    return instance;
}

} // namespace ringpoc

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeRingStart(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return ringpoc::ringEngine().start() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeRingStop(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return ringpoc::ringEngine().stop() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeRingSeek(
    JNIEnv* /*env*/, jobject /*thiz*/, jlong newFrame) {
    return ringpoc::ringEngine().seekToFrame(static_cast<int64_t>(newFrame))
        ? JNI_TRUE : JNI_FALSE;
}

// 반환 LongArray: [vf, ringHead, ringTail, silentCount, decodedCount, seekCount]
JNIEXPORT jlongArray JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeRingGetStats(
    JNIEnv* env, jobject /*thiz*/) {
    int64_t vf = 0, head = 0, tail = 0, silent = 0, decoded = 0, seekCount = 0;
    ringpoc::ringEngine().getStats(&vf, &head, &tail, &silent, &decoded, &seekCount);
    jlongArray arr = env->NewLongArray(6);
    const jlong values[6] = {vf, head, tail, silent, decoded, seekCount};
    env->SetLongArrayRegion(arr, 0, 6, values);
    return arr;
}

JNIEXPORT void JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeRingSetQueueFix(
    JNIEnv* /*env*/, jobject /*thiz*/, jboolean enabled) {
    ringpoc::ringEngine().setQueueFix(enabled == JNI_TRUE);
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeRingGetQueueFix(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return ringpoc::ringEngine().getQueueFix() ? JNI_TRUE : JNI_FALSE;
}

}
