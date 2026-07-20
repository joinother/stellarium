// =============================================================================
// stelrenderer.cpp —— 最小旋转的星空渲染 Item 实现
//
// 渲染策略（Qt 6.12 / HarmonyOS / OpenGL ES 3.2）：
//   - 用 QSGRenderNode 进入 Qt Quick 场景图渲染线程，在 Qt 已绑定好的
//     OpenGL ES 上下文里直接 glDrawArrays(GL_POINTS, ...)。
//   - 这里用极简顶点着色器 + 透视投影，把单位球面上的星点投影成屏幕点阵。
//   - angleX / angleY 由 QML 的拖拽/TouchHandler 驱动，实现"转动星空"。
// =============================================================================

#include "stelrenderer.h"

#include <QQuickWindow>
#include <QSGGeometry>
#include <QSGGeometryNode>
#include <QSGFlatColorMaterial>

#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QMatrix4x4>

#include <cmath>
#include <random>

// ---- 着色器（GLSL ES 3.20，鸿蒙 GLES 3.2 上下文） ------------------------
static const char *VERT_SRC =
    "#version 320 es\n"
    "in vec3 aPos;\n"
    "uniform mat4 uMVP;\n"
    "uniform float uPointSize;\n"
    "void main() {\n"
    "    gl_Position = uMVP * vec4(aPos, 1.0);\n"
    "    gl_PointSize = uPointSize;\n"
    "}\n";

static const char *FRAG_SRC =
    "#version 320 es\n"
    "precision mediump float;\n"
    "out vec4 fragColor;\n"
    "void main() {\n"
    "    // 圆形柔边星点\n"
    "    vec2 c = gl_PointCoord - vec2(0.5);\n"
    "    float d = dot(c, c);\n"
    "    if (d > 0.25) discard;\n"
    "    float a = smoothstep(0.25, 0.0, d);\n"
    "    fragColor = vec4(1.0, 1.0, 0.95, a);\n"
    "}\n";

// ----------------------------------------------------------------------------
StelRenderer::StelRenderer(QQuickItem *parent)
    : QQuickItem(parent)
{
    // 告知场景图：本 item 需要自己的渲染节点（而非默认矩形）
    setFlag(ItemHasContents, true);
}

StelRenderer::~StelRenderer() = default;

void StelRenderer::setAngleX(qreal a)
{
    if (!qFuzzyCompare(m_angleX, a)) {
        m_angleX = a;
        emit angleXChanged();
        update(); // 触发 updatePaintNode
    }
}

void StelRenderer::setAngleY(qreal a)
{
    if (!qFuzzyCompare(m_angleY, a)) {
        m_angleY = a;
        emit angleYChanged();
        update();
    }
}

void StelRenderer::ensureStarField()
{
    if (m_starFieldReady)
        return;
    // 在单位球面上均匀撒 800 个星点（用黄金螺旋分布，简单且无依赖）
    const int N = 800;
    m_stars.clear();
    const double golden = 3.141592653589793 * (3.0 - std::sqrt(5.0));
    for (int i = 0; i < N; ++i) {
        double y = 1.0 - (i / double(N - 1)) * 2.0; // 1 .. -1
        double r = std::sqrt(1.0 - y * y);
        double theta = golden * i;
        m_stars.append(QVector3D(
            float(std::cos(theta) * r),
            float(y),
            float(std::sin(theta) * r)));
    }
    m_starFieldReady = true;
}

QSGNode *StelRenderer::updatePaintNode(QSGNode *node, UpdatePaintNodeData *)
{
    ensureStarField();

    StelRenderNode *rn = static_cast<StelRenderNode *>(node);
    if (!rn) {
        rn = new StelRenderNode(this);
        // 把星点一次性交给渲染节点
        rn->setStars(m_stars);
    }
    rn->setAngles(m_angleX, m_angleY, boundingRect());
    return rn;
}

// 注入星点列表（友元式简化：用成员直接设置）
void StelRenderNode::setStars(const QList<QVector3D> &stars) { m_stars = stars; }

// ----------------------------------------------------------------------------
// StelRenderNode：真正画 GLES 的地方
// ----------------------------------------------------------------------------
StelRenderNode::StelRenderNode(StelRenderer *item)
    : m_item(item)
{
}

StelRenderNode::~StelRenderNode()
{
    releaseResources();
}

void StelRenderNode::setAngles(qreal ax, qreal ay, const QRectF &rect)
{
    m_angleX = ax;
    m_angleY = ay;
    m_rect = rect;
}

void StelRenderNode::initGL()
{
    if (m_glReady)
        return;

    QOpenGLFunctions *f = QOpenGLContext::currentContext()->functions();
    Q_UNUSED(f);

    // 编译着色器
    auto compile = [](GLenum type, const char *src) -> unsigned int {
        unsigned int s = glCreateShader(type);
        glShaderSource(s, 1, &src, nullptr);
        glCompileShader(s);
        return s;
    };

    unsigned int vs = compile(GL_VERTEX_SHADER, VERT_SRC);
    unsigned int fs = compile(GL_FRAGMENT_SHADER, FRAG_SRC);

    m_program = glCreateProgram();
    glAttachShader(m_program, vs);
    glAttachShader(m_program, fs);
    glLinkProgram(m_program);

    glDeleteShader(vs);
    glDeleteShader(fs);

    m_locMVP = glGetUniformLocation(m_program, "uMVP");
    m_locPointSize = glGetUniformLocation(m_program, "uPointSize");

    // 上传星点 VBO
    if (!m_stars.isEmpty()) {
        glGenBuffers(1, &m_vbo);
        glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
        glBufferData(GL_ARRAY_BUFFER,
                     m_stars.size() * 3 * sizeof(float),
                     m_stars.constData(),
                     GL_STATIC_DRAW);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
    }

    m_glReady = true;
}

void StelRenderNode::render(const RenderState *state)
{
    Q_UNUSED(state);

    QOpenGLFunctions *f = QOpenGLContext::currentContext()->functions();
    if (!f)
        return;

    initGL();

    // 视口（用 item 在窗口中的矩形）
    QRect r = m_rect.toRect();
    glViewport(r.x(), r.y(), r.width(), r.height());

    // 清成近黑的深蓝（夜空）
    glClearColor(0.02f, 0.03f, 0.08f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    glUseProgram(m_program);

    // 投影：透视 + 绕 X/Y 旋转（由触屏拖拽驱动）
    QMatrix4x4 proj;
    proj.perspective(60.0f, r.width() / qMax(1.0f, (float)r.height()), 0.1f, 100.0f);
    QMatrix4x4 view;
    view.translate(0.0f, 0.0f, -3.0f);
    QMatrix4x4 rot;
    rot.rotate(float(m_angleX), 1.0f, 0.0f, 0.0f);
    rot.rotate(float(m_angleY), 0.0f, 1.0f, 0.0f);
    QMatrix4x4 mvp = proj * view * rot;

    glUniformMatrix4fv(m_locMVP, 1, GL_FALSE, mvp.constData());
    glUniform1f(m_locPointSize, 6.0f * (m_item && m_item->window()
                                        ? m_item->window()->devicePixelRatio()
                                        : 1.0f));

    glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, 3 * sizeof(float), nullptr);
    glDrawArrays(GL_POINTS, 0, m_stars.size());
    glBindBuffer(GL_ARRAY_BUFFER, 0);
    glDisableVertexAttribArray(0);

    glUseProgram(0);
}

void StelRenderNode::releaseResources()
{
    if (!m_glReady)
        return;
    if (m_vbo)
        glDeleteBuffers(1, &m_vbo);
    if (m_program)
        glDeleteProgram(m_program);
    m_vbo = 0;
    m_program = 0;
    m_glReady = false;
}
