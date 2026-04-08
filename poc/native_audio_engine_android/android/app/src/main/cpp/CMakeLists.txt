cmake_minimum_required(VERSION 3.22.1)
project(oboe_engine)

# Oboe (prefab으로 가져옴, build.gradle.kts의 prefab=true + dependencies oboe)
find_package(oboe REQUIRED CONFIG)

add_library(oboe_engine SHARED
    oboe_engine.cpp
)

target_link_libraries(oboe_engine
    oboe::oboe
    log
    android
)
