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

#include <oboe/Oboe.h>
#include <jni.h>
#include <android/log.h>
#include <time.h>
#include <atomic>
#include <cmath>
#include <memory>
#include <mutex>

#define LOG_TAG "OboeEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

constexpr float kSineFrequencyHz = 440.0f;
constexpr float kAmplitude = 0.3f;
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
        int64_t* outWallAtFramePosNs) {
        std::lock_guard<std::mutex> lock(mLock);
        if (!mStream) {
            *outFramePos = -1;
            *outTimeNs = -1;
            *outWallAtFramePosNs = -1;
            return false;
        }
        int64_t framePos = 0;
        int64_t timeNs = 0;
        oboe::Result result = mStream->getTimestamp(CLOCK_MONOTONIC, &framePos, &timeNs);
        if (result != oboe::Result::OK) {
            *outFramePos = -1;
            *outTimeNs = -1;
            *outWallAtFramePosNs = -1;
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
        const double twoPiFreqOverSr =
            2.0 * M_PI * static_cast<double>(kSineFrequencyHz) / sr;
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
                // 비프 ON 구간: sine 생성 + fade 엔벨로프로 클릭 제거.
                const double phase = twoPiFreqOverSr * static_cast<double>(vf);
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
// 반환 배열: [framePos, timeNs, wallAtFramePosNs, ok(1|0)]
// wallAtFramePosNs는 "framePos가 DAC에 나간 순간의 CLOCK_REALTIME (ns)".
// Dart는 이걸 ms로 나눠서 "sample의 wall 시각"으로 사용 → framePos와 정합.
JNIEXPORT jlongArray JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeGetTimestamp(
    JNIEnv* env, jobject /*thiz*/) {
    int64_t framePos = -1;
    int64_t timeNs = -1;
    int64_t wallAtFramePosNs = -1;
    const bool ok = engine().getLatestTimestamp(
        &framePos, &timeNs, &wallAtFramePosNs);
    jlongArray arr = env->NewLongArray(4);
    const jlong values[4] = {
        framePos, timeNs, wallAtFramePosNs, ok ? 1L : 0L
    };
    env->SetLongArrayRegion(arr, 0, 4, values);
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
