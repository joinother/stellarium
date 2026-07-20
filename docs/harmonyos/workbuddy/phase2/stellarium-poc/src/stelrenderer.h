// =============================================================================
// stelrenderer.h —— 最小旋转的星空渲染 Item（C++ 自定义 QQuickItem）
//
// 适配要点：
//   - 使用 Qt Quick 场景图（Scene Graph）的 QSGRenderNode + QOpenGL 进行
//     OpenGL ES 3.2 绘制，符合 Qt 6.12 在鸿蒙上的渲染约定。
//   - 通过 QQuickItem 暴露 angleX / angleY 属性给 QML，触屏/鼠标拖拽修改
//     这两个角度即可旋转星空点阵，为后续 Stellarium 指星打基础。
//   - 不依赖旧 Qt OpenGL 模块（QOpenGLWidget 等），仅用 Qt Gui OpenGL。
// =============================================================================

#pragma once

#include <QQuickItem>
#include <QVector3D>
#include <QList>

class StelRenderer : public QQuickItem
{
    Q_OBJECT
    Q_PROPERTY(qreal angleX READ angleX WRITE setAngleX NOTIFY angleXChanged)
    Q_PROPERTY(qreal angleY READ angleY WRITE setAngleY NOTIFY angleYChanged)

public:
    explicit StelRenderer(QQuickItem *parent = nullptr);
    ~StelRenderer() override;

    qreal angleX() const { return m_angleX; }
    qreal angleY() const { return m_angleY; }

    void setAngleX(qreal a);
    void setAngleY(qreal a);

signals:
    void angleXChanged();
    void angleYChanged();

protected:
    // 注册场景图节点（真正执行 GLES 绘制的地方）
    QSGNode *updatePaintNode(QSGNode *node, UpdatePaintNodeData *data) override;

private:
    // 生成一批伪随机星空点（单位球面上的方向向量）
    void ensureStarField();

    qreal m_angleX = 0.0;
    qreal m_angleY = 0.0;

    QList<QVector3D> m_stars;   // 单位球面上的星点
    bool m_starFieldReady = false;
};

// 真正的 GLES 绘制节点：在鸿蒙 GLES 3.2 上下文里画点阵
class StelRenderNode : public QSGRenderNode
{
public:
    StelRenderNode(StelRenderer *item);
    ~StelRenderNode() override;

    // 鸿蒙：Qt 6.12 会在此回调里提供一个已绑定好的 OpenGL ES 上下文
    void render(const RenderState *state) override;
    void releaseResources() override;

    void setAngles(qreal ax, qreal ay, const QRectF &rect);
    void setStars(const QList<QVector3D> &stars);

private:
    void initGL();
    void drawStars();

    StelRenderer *m_item = nullptr;
    QList<QVector3D> m_stars;

    qreal m_angleX = 0.0;
    qreal m_angleY = 0.0;
    QRectF m_rect;

    unsigned int m_program = 0;
    int m_locMVP = -1;
    int m_locPointSize = -1;
    unsigned int m_vbo = 0;
    bool m_glReady = false;
};
