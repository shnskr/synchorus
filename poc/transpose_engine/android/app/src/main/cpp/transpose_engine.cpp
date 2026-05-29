// transpose_engine PoC — §H Transpose 격리 검증.
// step 3: Worker thread + lock-free SPSC ring buffer.
//   - Worker thread: sine generator → SoundTouch(4096 batch) → output ring
//   - Callback: output ring에서 pop만 (RT-safe, alloc/process 0)
//   - cents = 0 → bypass (callback이 sine 직접 생성, worker 결과 안 씀)
//
// step 2 (callback 안 처리) silence padding 한계 → step 3 worker로 fix.
// PoC 통과 기준: ±12 sweep click 0, timing drift ±10ms, glitch 0.

#include <oboe/Oboe.h>
#include <jni.h>
#include <android/log.h>
#include <atomic>
#include <cmath>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>
#include <algorithm>
#include "SoundTouch.h"

#define LOG_TAG "TransposeEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

constexpr float kPi = 3.14159265358979323846f;
constexpr float kSineFreq = 1000.0f;
constexpr float kSineAmp = 0.25f;
constexpr int kSampleRate = 48000;
constexpr size_t kWorkerBatchFrames = 4096;    // SoundTouch가 안정 처리하는 크기
constexpr size_t kOutRingFrames = 8192;        // ~170ms @48k — transition click 짧게

// Lock-free SPSC ring (interleaved stereo float).
// producer = worker, consumer = audio callback.
class SpscRing {
public:
    void init(size_t capacityFrames) {
        mCapacity = capacityFrames;
        mBuf.assign(capacityFrames * 2u, 0.0f);
        mHead.store(0, std::memory_order_relaxed);
        mTail.store(0, std::memory_order_relaxed);
    }

    size_t available() const {
        const size_t head = mHead.load(std::memory_order_acquire);
        const size_t tail = mTail.load(std::memory_order_acquire);
        return head - tail;
    }

    size_t space() const {
        return mCapacity - available();
    }

    bool push(const float* data, size_t frames) {
        const size_t head = mHead.load(std::memory_order_relaxed);
        const size_t tail = mTail.load(std::memory_order_acquire);
        if (frames > mCapacity - (head - tail)) return false;
        for (size_t i = 0; i < frames; ++i) {
            const size_t idx = (head + i) % mCapacity;
            mBuf[idx * 2u] = data[i * 2u];
            mBuf[idx * 2u + 1u] = data[i * 2u + 1u];
        }
        mHead.store(head + frames, std::memory_order_release);
        return true;
    }

    size_t pop(float* data, size_t maxFrames) {
        const size_t tail = mTail.load(std::memory_order_relaxed);
        const size_t head = mHead.load(std::memory_order_acquire);
        const size_t avail = head - tail;
        const size_t frames = std::min(maxFrames, avail);
        for (size_t i = 0; i < frames; ++i) {
            const size_t idx = (tail + i) % mCapacity;
            data[i * 2u] = mBuf[idx * 2u];
            data[i * 2u + 1u] = mBuf[idx * 2u + 1u];
        }
        mTail.store(tail + frames, std::memory_order_release);
        return frames;
    }

    void clear() {
        mHead.store(0, std::memory_order_release);
        mTail.store(0, std::memory_order_release);
    }

private:
    std::vector<float> mBuf;
    size_t mCapacity{0};
    std::atomic<size_t> mHead{0};
    std::atomic<size_t> mTail{0};
};

class TransposeEngine : public oboe::AudioStreamDataCallback {
public:
    TransposeEngine() {
        mST.setSampleRate(kSampleRate);
        mST.setChannels(2);
        mST.setPitchSemiTones(0.0f);
        // 음악용 setting (Olli Parviainen 공식 권장).
        mST.setSetting(SETTING_SEQUENCE_MS, 82);
        mST.setSetting(SETTING_SEEKWINDOW_MS, 28);
        mST.setSetting(SETTING_OVERLAP_MS, 12);
        mST.setSetting(SETTING_USE_AA_FILTER, 1);
        mST.setSetting(SETTING_USE_QUICKSEEK, 0);
        mOutRing.init(kOutRingFrames);
    }

    ~TransposeEngine() {
        stop();
    }

    bool start() {
        std::lock_guard<std::mutex> lock(mLock);
        if (mStream) return true;

        // Oboe stream 먼저 열고 worker 시작.
        oboe::AudioStreamBuilder builder;
        oboe::Result r = builder
            .setDirection(oboe::Direction::Output)
            ->setPerformanceMode(oboe::PerformanceMode::LowLatency)
            ->setSharingMode(oboe::SharingMode::Exclusive)
            ->setFormat(oboe::AudioFormat::Float)
            ->setChannelCount(2)
            ->setSampleRate(kSampleRate)
            ->setDataCallback(this)
            ->openStream(mStream);
        if (r != oboe::Result::OK) {
            LOGE("start openStream: %s", oboe::convertToText(r));
            mStream.reset();
            return false;
        }

        // Worker thread 시작.
        mOutRing.clear();
        mWorkerPhase = 0.0f;
        mCallbackPhase = 0.0f;
        mWorkerRunning.store(true, std::memory_order_release);
        mPitchDirty.store(true, std::memory_order_release);
        mWorker = std::thread(&TransposeEngine::workerLoop, this);

        r = mStream->requestStart();
        if (r != oboe::Result::OK) {
            LOGE("start requestStart: %s", oboe::convertToText(r));
            mWorkerRunning.store(false, std::memory_order_release);
            if (mWorker.joinable()) mWorker.join();
            mStream->close();
            mStream.reset();
            return false;
        }
        LOGI("start: sr=%d burst=%d cents=%d worker batch=%zu ring=%zu",
             mStream->getSampleRate(), mStream->getFramesPerBurst(),
             mCents.load(), kWorkerBatchFrames, kOutRingFrames);
        return true;
    }

    bool stop() {
        std::lock_guard<std::mutex> lock(mLock);
        // Worker thread 정리 (stream stop 전 — pop은 의미 없어짐).
        mWorkerRunning.store(false, std::memory_order_release);
        if (mWorker.joinable()) mWorker.join();

        if (mStream) {
            mStream->requestStop();
            mStream->close();
            mStream.reset();
        }
        mST.clear();
        mOutRing.clear();
        LOGI("stop");
        return true;
    }

    void setCents(int cents) {
        const int clamped = std::max(-1200, std::min(1200, cents));
        mCents.store(clamped, std::memory_order_release);
        mPitchDirty.store(true, std::memory_order_release);
    }

    int getCents() const {
        return mCents.load(std::memory_order_acquire);
    }

    // Audio callback — RT-safe (alloc/lock/process 0).
    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* stream,
        void* audioData,
        int32_t numFrames) override {

        float* output = static_cast<float*>(audioData);
        const int outCh = stream->getChannelCount();
        const int sr = stream->getSampleRate();
        const int currentCents = mCents.load(std::memory_order_acquire);

        if (outCh != 2) {
            // mono fallback (PoC는 stereo 가정, 진단용)
            memset(output, 0,
                   static_cast<size_t>(numFrames * outCh) * sizeof(float));
            return oboe::DataCallbackResult::Continue;
        }

        // 1. Bypass (cents=0) — callback에서 sine 직접 생성. 음질 손실 0.
        if (currentCents == 0) {
            const float dPhase = 2.0f * kPi * kSineFreq /
                static_cast<float>(sr);
            for (int i = 0; i < numFrames; ++i) {
                const float s = std::sin(mCallbackPhase) * kSineAmp;
                mCallbackPhase += dPhase;
                if (mCallbackPhase > 2.0f * kPi) mCallbackPhase -= 2.0f * kPi;
                output[i * 2] = s;
                output[i * 2 + 1] = s;
            }
            return oboe::DataCallbackResult::Continue;
        }

        // 2. Transpose 적용 — output ring에서 numFrames pop.
        const size_t popped = mOutRing.pop(output, static_cast<size_t>(numFrames));
        if (popped < static_cast<size_t>(numFrames)) {
            // Worker가 안 따라옴 (underrun). silence 채움.
            memset(output + popped * 2u, 0,
                   (static_cast<size_t>(numFrames) - popped) * 2u * sizeof(float));
            mUnderrunCount.fetch_add(1, std::memory_order_relaxed);
        }
        return oboe::DataCallbackResult::Continue;
    }

    int getUnderrunCount() const {
        return mUnderrunCount.load(std::memory_order_relaxed);
    }

private:
    // Worker thread: input sine 생성 → SoundTouch → output ring push.
    // RT 외 thread이므로 alloc/sleep/lock OK.
    void workerLoop() {
        std::vector<float> inBuf(kWorkerBatchFrames * 2u);
        std::vector<float> outBuf(kWorkerBatchFrames * 2u);
        LOGI("worker started");

        while (mWorkerRunning.load(std::memory_order_acquire)) {
            // pitch 갱신 — worker thread 단독으로 sonic API 호출 (SoundTouch thread-safe X).
            if (mPitchDirty.exchange(false, std::memory_order_acq_rel)) {
                mST.clear();
                mST.setPitchSemiTones(mCents.load(std::memory_order_acquire) / 100.0f);
                mOutRing.clear();
            }

            // output ring 여유분 확인 — 부족하면 잠시 대기.
            if (mOutRing.space() < kWorkerBatchFrames) {
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
                continue;
            }

            // input sine 생성 (worker phase).
            const float dPhase = 2.0f * kPi * kSineFreq /
                static_cast<float>(kSampleRate);
            for (size_t i = 0; i < kWorkerBatchFrames; ++i) {
                const float s = std::sin(mWorkerPhase) * kSineAmp;
                mWorkerPhase += dPhase;
                if (mWorkerPhase > 2.0f * kPi) mWorkerPhase -= 2.0f * kPi;
                inBuf[i * 2u] = s;
                inBuf[i * 2u + 1u] = s;
            }

            // SoundTouch process — 가능한 만큼 output 모두 받음.
            mST.putSamples(inBuf.data(),
                static_cast<unsigned int>(kWorkerBatchFrames));
            unsigned int received = 0;
            do {
                received = mST.receiveSamples(outBuf.data(),
                    static_cast<unsigned int>(kWorkerBatchFrames));
                if (received > 0) {
                    while (!mOutRing.push(outBuf.data(), received) &&
                           mWorkerRunning.load(std::memory_order_acquire)) {
                        // ring 가득 — 잠시 대기 후 재시도.
                        std::this_thread::sleep_for(std::chrono::milliseconds(1));
                    }
                }
            } while (received == kWorkerBatchFrames);
        }
        LOGI("worker stopped");
    }

    std::shared_ptr<oboe::AudioStream> mStream;
    soundtouch::SoundTouch mST;
    std::atomic<int> mCents{0};
    std::atomic<bool> mPitchDirty{false};
    std::atomic<bool> mWorkerRunning{false};
    std::thread mWorker;
    SpscRing mOutRing;
    float mWorkerPhase{0.0f};     // worker thread 단독 read/write
    float mCallbackPhase{0.0f};   // callback thread 단독 read/write
    std::atomic<int> mUnderrunCount{0};
    std::mutex mLock;             // start/stop 직렬화
};

TransposeEngine& engine() {
    static TransposeEngine instance;
    return instance;
}

} // namespace

extern "C" {

JNIEXPORT void JNICALL
Java_com_synchorus_transpose_1engine_NativeTranspose_nativeInit(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    LOGI("init: SoundTouch %s", soundtouch::SoundTouch::getVersionString());
    (void)engine();
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_transpose_1engine_NativeTranspose_nativeStart(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().start() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_synchorus_transpose_1engine_NativeTranspose_nativeStop(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return engine().stop() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_synchorus_transpose_1engine_NativeTranspose_nativeSetCents(
    JNIEnv* /*env*/, jobject /*thiz*/, jint cents) {
    engine().setCents(static_cast<int>(cents));
}

JNIEXPORT jint JNICALL
Java_com_synchorus_transpose_1engine_NativeTranspose_nativeGetCents(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return static_cast<jint>(engine().getCents());
}

JNIEXPORT jint JNICALL
Java_com_synchorus_transpose_1engine_NativeTranspose_nativeGetUnderrunCount(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    return static_cast<jint>(engine().getUnderrunCount());
}

} // extern "C"
