cmake_minimum_required(VERSION 3.22.1)
project(oboe_engine)

find_package(oboe REQUIRED CONFIG)

add_library(oboe_engine SHARED
    oboe_engine.cpp
)

target_link_libraries(oboe_engine
    oboe::oboe
    mediandk
    log
    android
)
