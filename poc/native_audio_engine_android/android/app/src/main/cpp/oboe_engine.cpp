// PoC Phase 0: Oboe 래퍼 + 단순 sine wave 재생
// 통과 기준: 440Hz 톤이 디바이스에서 들림
//
// 다음 단계 (Phase 1)에서 getTimestamp 폴링 추가 예정.

#include <oboe/Oboe.h>
#include <jni.h>
#include <android/log.h>
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

        mPhase = 0.0;
        mPhaseIncrement = 2.0 * M_PI * kSineFrequencyHz / mStream->getSampleRate();
        LOGI("openStream OK: sampleRate=%d framesPerBurst=%d",
             mStream->getSampleRate(), mStream->getFramesPerBurst());

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
    bool getLatestTimestamp(int64_t* outFramePos, int64_t* outTimeNs) {
        std::lock_guard<std::mutex> lock(mLock);
        if (!mStream) {
            *outFramePos = -1;
            *outTimeNs = -1;
            return false;
        }
        int64_t framePos = 0;
        int64_t timeNs = 0;
        oboe::Result result = mStream->getTimestamp(CLOCK_MONOTONIC, &framePos, &timeNs);
        if (result != oboe::Result::OK) {
            *outFramePos = -1;
            *outTimeNs = -1;
            return false;
        }
        *outFramePos = framePos;
        *outTimeNs = timeNs;
        return true;
    }

    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* stream,
        void* audioData,
        int32_t numFrames) override {
        auto* output = static_cast<float*>(audioData);
        const int channelCount = stream->getChannelCount();
        for (int i = 0; i < numFrames; ++i) {
            const float sample = static_cast<float>(std::sin(mPhase)) * kAmplitude;
            for (int ch = 0; ch < channelCount; ++ch) {
                *output++ = sample;
            }
            mPhase += mPhaseIncrement;
            if (mPhase >= 2.0 * M_PI) mPhase -= 2.0 * M_PI;
        }
        return oboe::DataCallbackResult::Continue;
    }

private:
    std::shared_ptr<oboe::AudioStream> mStream;
    double mPhase = 0.0;
    double mPhaseIncrement = 0.0;
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
// 반환 배열: [framePos, timeNs, ok(1|0)]
JNIEXPORT jlongArray JNICALL
Java_com_synchorus_poc_native_1audio_1engine_1android_NativeAudio_nativeGetTimestamp(
    JNIEnv* env, jobject /*thiz*/) {
    int64_t framePos = -1;
    int64_t timeNs = -1;
    const bool ok = engine().getLatestTimestamp(&framePos, &timeNs);
    jlongArray arr = env->NewLongArray(3);
    const jlong values[3] = { framePos, timeNs, ok ? 1L : 0L };
    env->SetLongArrayRegion(arr, 0, 3, values);
    return arr;
}

}
