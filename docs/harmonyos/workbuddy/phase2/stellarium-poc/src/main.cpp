// =============================================================================
// main.cpp —— Qt Quick 应用入口（Qt for HarmonyOS 约定）
//
// 适配要点：
//   - QGuiApplication + QQmlApplicationEngine 加载 qml（资源内嵌）。
//   - 在鸿蒙上，本可执行被编译为 .so 并由 harmonydeployqt 包装；导出 main
//     供鸿蒙侧 QPA 启动调用（见下方 extern "C" 入口）。
//   - 启用 OpenGL ES 渲染：Qt 6.12 会自动检测鸿蒙的 GLES 上下文，无需手动
//     指定桌面 OpenGL。
// =============================================================================

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QOpenGLContext>

#include "stelrenderer.h"

int stellarium_poc_main(int argc, char *argv[])
{
    // 提示 Qt 优先使用 OpenGL（Qt 6.12 在鸿蒙会自动落到 GLES 3.2）
    qputenv("QT_OPENGL", "angle"); // 仅作保险；鸿蒙 QPA 会接管

    QGuiApplication app(argc, argv);
    app.setApplicationName("Stellarium PoC");
    app.setOrganizationName("StellariumHarmonyPort");

    // 注册自定义渲染 Item 到 QML（供 stel_poc.qml 使用）
    qmlRegisterType<StelRenderer>("Stel.Poc", 1, 0, "StelRenderer");

    QQmlApplicationEngine engine;

    // 加载内嵌 qml 资源（CMake 中 qt_add_resources 已把 stel_poc.qml 编进二进制）
    const QUrl url(QStringLiteral("qrc:/src/stel_poc.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &loaded) {
                         if (!obj && url == loaded)
                             qWarning("Stellarium PoC: QML 加载失败，请检查 stel_poc.qml 资源路径。");
                     }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}

// ----------------------------------------------------------------------------
// 鸿蒙入口：Qt for HarmonyOS 约定导出 main 符号（C 链接）
// harmonydeployqt 包装后的应用会调用此符号启动 Qt 应用。
// ----------------------------------------------------------------------------
extern "C" int main(int argc, char *argv[])
{
    return stellarium_poc_main(argc, argv);
}
