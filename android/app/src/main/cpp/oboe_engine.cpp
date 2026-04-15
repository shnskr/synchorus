// Oboe 네이티브 오디오 엔진 — PoC에서 검증 완료, 본체 앱으로 이식.
// 현재: 음계 비프(C4~C5) 생성. 추후: 오디오 파일 디코딩 재생으로 교체.

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

constexpr float kAmplitude = 0.3f;
constexpr float kNoteFrequencies[] = {
    261.63f, 293.66f, 329.63f, 349.23f,
    392.00f, 440.00f, 493.88f, 523.25f,
};
constexpr int kNumNotes = sizeof(kNoteFrequencies) / sizeof(kNoteFrequencies[0]);
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
        struct timespec wallTs;
        struct timespec monoTs;
        clock_gettime(CLOCK_REALTIME, &wallTs);
        clock_gettime(CLOCK_MONOTONIC, &monoTs);
        const int64_t wallNow =
            static_cast<int64_t>(wallTs.tv_sec) * 1000000000LL + wallTs.tv_nsec;
        const int64_t monoNow =
            static_cast<int64_t>(monoTs.tv_sec) * 1000000000LL + monoTs.tv_nsec;
        const int64_t gap = monoNow - timeNs;
        *outFramePos = framePos;
        *outTimeNs = timeNs;
        *outWallAtFramePosNs = wallNow - gap;
        *outVirtualFrame = mVirtualFrame.load(std::memory_order_relaxed);
        return true;
    }

    int64_t getVirtualFrame() const {
        return mVirtualFrame.load(std::memory_order_relaxed);
    }

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
        const int64_t beepPeriodFrames =
            static_cast<int64_t>(static_cast<double>(kBeepPeriodSec) * sr);
        const int64_t beepDurationFrames =
            static_cast<int64_t>(static_cast<double>(kBeepDurationSec) * sr);
        const int64_t beepFadeFrames =
            static_cast<int64_t>(static_cast<double>(kBeepFadeSec) * sr);
        int64_t vf = mVirtualFrame.load(std::memory_order_relaxed);
        for (int i = 0; i < numFrames; ++i) {
            int64_t mod = vf % beepPeriodFrames;
            if (mod < 0) mod += beepPeriodFrames;

            float sample = 0.0f;
            if (mod < beepDurationFrames) {
                const int64_t beatIndex = (vf - mod) / beepPeriodFrames;
                const int noteIdx = static_cast<int>(
                    ((beatIndex % kNumNotes) + kNumNotes) % kNumNotes);
                const double freq = static_cast<double>(kNoteFrequencies[noteIdx]);
                const double phase = 2.0 * M_PI * freq
                    * static_cast<double>(mod) / sr;
                float env = 1.0f;
                if (mod < beepFadeFrames) {
                    env = static_cast<float>(mod)
                        / static_cast<float>(beepFadeFrames);
                } else if (mod >= beepDurationFrames - beepFadeFrames) {
                    const int64_t remaining = beepDurationFrames - mod;
                    env = static_cast<float>(remaining)
                        / static_cast<float>(beepFadeFrames);
                }
                sample = static_cast<float>(std::sin(phase)) * kAmplitude * env;
            }
            for (int ch = 0; ch < channelCount; ++ch) {
                *output++ = sample;
            }
            ++vf;
        }
        mVirtualFrame.store(vf, std::memory_order_relaxed);
        return oboe::DataCallbackResult::Continue;
    }

private:
    std::shared_ptr<oboe::AudioStream> mStream;
    int32_t mSampleRate = 48000;
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

JNIEXPORT jboolean JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeSeekToFrame(
    JNIEnv* /*env*/, jobject /*thiz*/, jlong newFrame) {
    return engine().seekToFrame(static_cast<int64_t>(newFrame)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jlong JNICALL
Java_com_synchorus_synchorus_NativeAudio_nativeGetVirtualFrame(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return static_cast<jlong>(engine().getVirtualFrame());
}

}
