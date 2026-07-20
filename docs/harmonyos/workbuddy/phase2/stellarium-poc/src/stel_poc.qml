// =============================================================================
// stel_poc.qml —— Qt Quick 主窗口
//
// 适配要点：
//   - 用自定义 StelRenderer（C++ QQuickItem）做 OpenGL ES 星空渲染。
//   - 单指拖拽（TouchHandler）+ 鼠标拖拽共同驱动旋转角 angleX/angleY，
//     验证"触屏可旋转场景"，为后续 Stellarium 指星交互打基础。
//   - 背景设为透明/深色，星空在 C++ 端清屏为夜空蓝。
// =============================================================================

import QtQuick
import QtQuick.Controls
import Stel.Poc 1.0

ApplicationWindow {
    id: root
    visible: true
    width: 720
    height: 1280
    title: "Stellarium Harmony PoC"
    color: "#04060f"   // 夜空底色，C++ 端也会清屏

    // ---------- 渲染层：可旋转的星空点阵 ----------
    StelRenderer {
        id: starfield
        anchors.fill: parent
        angleX: 0
        angleY: 0
    }

    // ---------- 触屏单指拖拽 + 鼠标拖拽 ----------
    // 用 DragHandler 统一处理鼠标与单指触摸（鸿蒙触屏映射为单指 pointer）。
    // 通过 centroid 增量驱动旋转角，实现"转动星空"。
    property real lastX: 0
    property real lastY: 0

    DragHandler {
        target: null
        onCentroidChanged: {
            if (active) {
                if (lastX === 0 && lastY === 0) {
                    lastX = centroid.x
                    lastY = centroid.y
                }
                var dx = centroid.x - lastX
                var dy = centroid.y - lastY
                lastX = centroid.x
                lastY = centroid.y
                starfield.angleY += dx * 0.3   // 水平拖 -> 绕 Y 轴
                starfield.angleX += dy * 0.3   // 垂直拖 -> 绕 X 轴
            } else {
                lastX = 0
                lastY = 0
            }
        }
    }

    // ---------- 提示文字 ----------
    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 24
        text: "Stellarium PoC · 单指/鼠标拖拽旋转星空"
        color: "#aaccff"
        font.pixelSize: 18
    }

    Label {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        text: "angleX: " + starfield.angleX.toFixed(1) +
              "  angleY: " + starfield.angleY.toFixed(1)
        color: "#6688cc"
        font.pixelSize: 14
    }
}
