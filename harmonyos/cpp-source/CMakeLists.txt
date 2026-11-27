# the minimum version of CMake.
cmake_minimum_required(VERSION 3.4.1)
project(ohosQtTemplate)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

include_directories(${NATIVERENDER_ROOT_PATH}
                    ${NATIVERENDER_ROOT_PATH}/include)

add_library(entry SHARED hello.cpp DetailModelNative.cpp AetherisAudioNative.cpp)
set_source_files_properties(DetailModelNative.cpp AetherisAudioNative.cpp PROPERTIES COMPILE_OPTIONS "-O3")
target_link_libraries(entry PUBLIC libace_napi.z.so libace_ndk.z.so libEGL.so libGLESv3.so libhilog_ndk.z.so libnative_image.so)
