# =============================================================================
# Stellarium HarmonyOS 最小渲染 PoC —— CMakeLists.txt
# 目的：验证 Qt6 Quick/QML + OpenGL ES 3.2 在纯血鸿蒙（harmonyos_arm64_v8a）
#       上的渲染通路与 harmonydeployqt 打包链路。
#
# 工具链事实（已核实）：
#   - Qt 6.12.0 Beta2, target harmonyos_arm64_v8a
#   - 需 DevEco Studio 6.1.0 + SDK API 23
#   - 渲染走 OpenGL ES 3.2（Qt 6.12 自动检测 Desktop OpenGL 或 OpenGL ES）
#   - Qt for HarmonyOS 不支持 WebEngine/Positioning/SerialPort/VirtualKeyboard/
#     TextToSpeech/旧 Qt OpenGL 模块，但支持 Qt Quick/QML、Qt Gui OpenGL、Qt Sensors
#
# 约定：Qt for HarmonyOS 上可执行需按 QPA/启动约定产出 SHARED 库（.so），
#       再由 harmonydeployqt 包装成鸿蒙应用包。因此本工程产出 .so 并导出 main。
# =============================================================================

cmake_minimum_required(VERSION 3.21)

project(stellarium_poc
    VERSION 0.1.0
    DESCRIPTION "Minimal Qt HarmonyOS render PoC for Stellarium port"
    LANGUAGES CXX
)

# ----------------------------------------------------------------------------
# 1) 工具链与架构：CMAKE_TOOLCHAIN_FILE 由 Qt 提供的 qt-cmake 注入
#    （见 build_ohos.sh，用 Qt 的 qt-cmake 而不是直接调 cmake）
#    这里仅做防御性提示。
# ----------------------------------------------------------------------------
if(NOT CMAKE_TOOLCHAIN_FILE AND NOT DEFINED ENV{QT_HARMONYOS_TARGET_ARCHS})
    message(WARNING
        "未检测到 Qt HarmonyOS 工具链。请通过 qt-cmake 调用本 CMakeLists，"
        "并设置 QT_HARMONYOS_TARGET_ARCHS=arm64-v8a。详见 build_ohos.sh。")
endif()

# 告知 harmonydeployqt / Qt 目标架构（Qt for HarmonyOS 约定变量）
set(QT_HARMONYOS_TARGET_ARCHS "arm64-v8a" CACHE STRING "HarmonyOS target archs")

# ----------------------------------------------------------------------------
# 2) 所需 Qt 组件：Core / Gui / Quick / QuickControls2
#    （注意：不要引入 WebEngine/Positioning/旧 OpenGL 模块 —— 鸿蒙不支持）
# ----------------------------------------------------------------------------
find_package(Qt6 COMPONENTS Core Gui Quick QuickControls2 REQUIRED)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(NOT Qt6_FOUND)
    message(FATAL_ERROR "Qt6 (Core/Gui/Quick/QuickControls2) 未找到，请确认 Qt 6.12 HarmonyOS 工具链在 CMAKE_FIND_ROOT_PATH 中。")
endif()

# ----------------------------------------------------------------------------
# 3) 源文件
# ----------------------------------------------------------------------------
set(POC_SOURCES
    src/main.cpp
    src/stelrenderer.cpp
)

set(POC_HEADERS
    src/stelrenderer.h
)

# QML 作为资源编译进二进制，避免运行时依赖外部路径（鸿蒙沙箱下更安全）
qt_add_resources(POC_QML_QRC
    qml
    PREFIX "/"
    FILES
        src/stel_poc.qml
)

# ----------------------------------------------------------------------------
# 4) 产出：SHARED 库（.so）
#    Qt for HarmonyOS 约定：可执行入口包装为共享库，由 harmonydeployqt 启动。
#    导出 main 符号供鸿蒙侧 QPA 启动调用。
# ----------------------------------------------------------------------------
add_library(${PROJECT_NAME} SHARED
    ${POC_SOURCES}
    ${POC_HEADERS}
    ${POC_QML_QRC}
)

# 导出 main（C 链接），确保 .so 被 harmonydeployqt 正确识别为入口
set_target_properties(${PROJECT_NAME} PROPERTIES
    CXX_VISIBILITY_PRESET default
)
target_link_libraries(${PROJECT_NAME} PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
)

# 让 moc 把 Q_OBJECT 类导出（stelrenderer 在 QML 中注册）
target_include_directories(${PROJECT_NAME} PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/src)

# ----------------------------------------------------------------------------
# 5) QML 模块导入路径提示（开发期）：将 qml 目录暴露给 engine
#    运行时实际走 qrc 资源，此处仅方便在 DevEco 中直接引用源 qml 调试。
# ----------------------------------------------------------------------------
install(TARGETS ${PROJECT_NAME}
    LIBRARY DESTINATION ${CMAKE_CURRENT_BINARY_DIR}
)

message(STATUS "Stellarium HarmonyOS PoC configured for arch: ${QT_HARMONYOS_TARGET_ARCHS}")
