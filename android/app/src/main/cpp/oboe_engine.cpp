// Oboe 네이티브 오디오 엔진 — step 1-2: 오디오 파일 디코딩 재생.
// NDK AMediaCodec으로 디코딩 → int16 버퍼 → Oboe float 출력.

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
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <media/NdkMediaExtractor.h>
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaFormat.h>

#define LOG_TAG "OboeEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

namespace {

class OboeEngine : public oboe::AudioStreamDataCallback {
public:
    bool loadFile(const char* path) {
        stop();

        mDecodedData.clear();
        mDecodedChannels = 0;
        mDecodedSampleRate = 0;
        mDecodedTotalFrames = 0;
        mFileLoaded = false;

        int fd = open(path, O_RDONLY);
        if (fd < 0) {
            LOGE("loadFile: open failed: %s", path);
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
            AMediaExtractor_delete(extractor);
            return false;
        }

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

        AMediaCodec* codec = AMediaCodec_createDecoderByType(mime);
        if (!codec) {
            LOGE("loadFile: createDecoder failed: %s", mime);
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

        // Reserve buffer (limit ~150MB int16)
        int64_t estFrames = (durationUs * sampleRate) / 1000000LL;
        int64_t estBytes = estFrames * channelCount * static_cast<int64_t>(sizeof(int16_t));
        if (estBytes > 150LL * 1024 * 1024) {
            LOGE("loadFile: too large (%lld MB est)",
                 static_cast<long long>(estBytes / (1024 * 1024)));
            AMediaCodec_stop(codec);
            AMediaCodec_delete(codec);
            AMediaExtractor_delete(extractor);
            return false;
        }
        if (estFrames > 0) {
            mDecodedData.reserve(
                static_cast<size_t>(estFrames * channelCount));
        }

        // Decode loop
        bool inputEos = false;
        bool outputEos = false;

        while (!outputEos) {
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

            AMediaCodecBufferInfo info;
            ssize_t outIdx = AMediaCodec_dequeueOutputBuffer(codec, &info, 10000);

            if (outIdx >= 0) {
                if (info.size > 0) {
                    size_t outSize = 0;
                    uint8_t* outBuf = AMediaCodec_getOutputBuffer(
                        codec, static_cast<size_t>(outIdx), &outSize);
                    int numSamples = info.size / static_cast<int>(sizeof(int16_t));
                    const auto* samples = reinterpret_cast<const int16_t*>(
                        outBuf + info.offset);
                    mDecodedData.insert(
                        mDecodedData.end(), samples, samples + numSamples);
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

        AMediaCodec_stop(codec);
        AMediaCodec_delete(codec);
        AMediaExtractor_delete(extractor);

        mDecodedChannels = channelCount;
        mDecodedSampleRate = sampleRate;
        mDecodedTotalFrames = static_cast<int64_t>(
            mDecodedData.size()) / channelCount;
        mFileLoaded = true;
        mVirtualFrame.store(0, std::memory_order_relaxed);

        LOGI("decode done: %lld frames, %d ch, %d Hz, %.1fs, %.1f MB",
             static_cast<long long>(mDecodedTotalFrames),
             mDecodedChannels, mDecodedSampleRate,
             static_cast<double>(mDecodedTotalFrames) / mDecodedSampleRate,
             static_cast<double>(mDecodedData.size() * sizeof(int16_t))
                 / (1024.0 * 1024.0));

        return true;
    }

    bool start() {
        std::lock_guard<std::mutex> lock(mLock);
        if (mStream) return true;
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
        oboe::Result result = mStream->getTimestamp(
            CLOCK_MONOTONIC, &framePos, &timeNs);
        if (result != oboe::Result::OK) {
            *outFramePos = -1;
            *outTimeNs = -1;
            *outWallAtFramePosNs = -1;
            *outVirtualFrame = 0;
            return false;
        }

        struct timespec wallTs, monoTs;
        clock_gettime(CLOCK_REALTIME, &wallTs);
        clock_gettime(CLOCK_MONOTONIC, &monoTs);
        const int64_t wallNow =
            static_cast<int64_t>(wallTs.tv_sec) * 1000000000LL + wallTs.tv_nsec;
        const int64_t monoNow =
            static_cast<int64_t>(monoTs.tv_sec) * 1000000000LL + monoTs.tv_nsec;

        *outFramePos = framePos;
        *outTimeNs = timeNs;
        *outWallAtFramePosNs = wallNow - (monoNow - timeNs);
        *outVirtualFrame = mVirtualFrame.load(std::memory_order_relaxed);
        return true;
    }

    int64_t getVirtualFrame() const {
        return mVirtualFrame.load(std::memory_order_relaxed);
    }

    bool seekToFrame(int64_t newFrame) {
        if (!mFileLoaded) return false;
        int64_t clamped = std::max(
            int64_t(0), std::min(newFrame, mDecodedTotalFrames));
        mVirtualFrame.store(clamped, std::memory_order_relaxed);
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
        int64_t vf = mVirtualFrame.load(std::memory_order_relaxed);

        for (int i = 0; i < numFrames; ++i) {
            for (int ch = 0; ch < outCh; ++ch) {
                float sample = 0.0f;
                if (mFileLoaded && vf >= 0 && vf < mDecodedTotalFrames) {
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
    std::shared_ptr<oboe::AudioStream> mStream;
    int32_t mStreamSampleRate = 48000;
    std::atomic<int64_t> mVirtualFrame{0};
    std::mutex mLock;

    std::vector<int16_t> mDecodedData;
    int32_t mDecodedChannels = 0;
    int32_t mDecodedSampleRate = 0;
    int64_t mDecodedTotalFrames = 0;
    bool mFileLoaded = false;
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

}
