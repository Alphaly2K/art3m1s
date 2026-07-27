cmake_minimum_required(VERSION 3.22.1)
project("art3m1s_jni" LANGUAGES CXX)

add_library(art3m1s_jni SHARED art3m1s_jni.cpp)

# JNI 头文件由 Android NDK 自动提供，无需额外 include。
target_compile_features(art3m1s_jni PRIVATE cxx_std_17)
