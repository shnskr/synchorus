cmake_minimum_required(VERSION 3.22.1)
project(oboe_engine)

find_package(oboe REQUIRED CONFIG)

# §H SoundTouch (Olli Parviainen, LGPL v2.1) 2.4.1 — pitch shift용.
# 본 앱 통합 v0.0.91 (worker thread + ring buffer 패턴, PoC 격리 검증 후).
set(SOUNDTOUCH_DIR ${CMAKE_CURRENT_SOURCE_DIR}/SoundTouch)
add_library(oboe_engine SHARED
    oboe_engine.cpp
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

target_include_directories(oboe_engine PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/SoundTouchInclude
)

target_compile_definitions(oboe_engine PRIVATE
    SOUNDTOUCH_FLOAT_SAMPLES
)

target_link_libraries(oboe_engine
    oboe::oboe
    mediandk
    log
    android
)
