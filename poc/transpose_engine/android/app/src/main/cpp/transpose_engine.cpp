// transpose_engine PoC — §H Transpose 격리 검증.
// 첫 단계: build 통과 + JNI stub. Oboe stream + SoundTouch 통합은 다음 commit.

#include <oboe/Oboe.h>
#include <jni.h>
#include <android/log.h>
#include "SoundTouch.h"

#define LOG_TAG "TransposeEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)

extern "C" {

JNIEXPORT void JNICALL
Java_com_synchorus_transpose_1engine_NativeTranspose_nativeInit(
    JNIEnv* /*env*/, jobject /*thiz*/) {
    // SoundTouch + Oboe symbol 검증용.
    soundtouch::SoundTouch st;
    st.setSampleRate(48000);
    st.setChannels(2);
    LOGI("init: SoundTouch %s, Oboe symbols linked",
         soundtouch::SoundTouch::getVersionString());
}

} // extern "C"
