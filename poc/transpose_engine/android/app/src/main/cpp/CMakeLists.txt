cmake_minimum_required(VERSION 3.22.1)
project(transpose_engine)

find_package(oboe REQUIRED CONFIG)

set(SOUNDTOUCH_DIR ${CMAKE_CURRENT_SOURCE_DIR}/SoundTouch)

# SoundTouch (Olli Parviainen, LGPL v2.1) 2.4.1
# x86 SSE/MMX optimized 파일도 포함 — x86 빌드(에뮬레이터) linker 통과용.
# ARM 빌드에선 #ifdef로 빈 implementation.
add_library(transpose_engine SHARED
    transpose_engine.cpp
    ${SOUNDTOUCH_DIR}/SoundTouch.cpp
    ${SOUNDTOUCH_DIR}/RateTransposer.cpp
    ${SOUNDTOUCH_DIR}/TDStretch.cpp
    ${SOUNDTOUCH_DIR}/AAFilter.cpp
    ${SOUNDTOUCH_DIR}/FIRFilter.cpp
    ${SOUNDTOUCH_DIR}/FIFOSampleBuffer.cpp
    ${SOUNDTOUCH_DIR}/InterpolateCubic.cpp
    ${SOUNDTOUCH_DIR}/InterpolateLinear.cpp
    ${SOUNDTOUCH_DIR}/InterpolateShannon.cpp
    ${SOUNDTOUCH_DIR}/cpu_detect_x86.cpp
    ${SOUNDTOUCH_DIR}/mmx_optimized.cpp
    ${SOUNDTOUCH_DIR}/sse_optimized.cpp
)

target_include_directories(transpose_engine PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/SoundTouchInclude
)

# float sample 사용 (Oboe stream과 일관). 디폴트 short(16-bit).
target_compile_definitions(transpose_engine PRIVATE
    SOUNDTOUCH_FLOAT_SAMPLES
)

target_link_libraries(transpose_engine
    oboe::oboe
    log
    android
)
