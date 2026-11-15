#include "VecMath.hpp"
#include <QGuiApplication>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QOpenGLBuffer>
#include <QOpenGLFramebufferObject>
#include <QOpenGLShaderProgram>
#include <QOpenGLVertexArrayObject>
#include <QVector3D>
#include <algorithm>
#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <iostream>
#include <memory>
#include <vector>

#define GL(expression) expression
namespace StelOpenGL { QOpenGLContext* mainContext = nullptr; }
struct StelCore {};
struct StelLocation {};
struct Planet
{
    Vec3d position{1., 0., 0.};
    float magnitude = -12.f;
    QString getEnglishName() const { return "Earth"; }
    Vec3d getAltAzPosAuto(const StelCore*) const { return position; }
    double getEquatorialRadius() const { return 0.001; }
    float getVMagnitude(const StelCore*) const { return magnitude; }
};
namespace StelUtils
{
double sunVisibilityDueToMoon(double, double, double separation) { return separation > 0.01 ? 1. : 0.; }
}
constexpr int PREP_FBO_WIDTH = 1024, PREP_FBO_HEIGHT = 512;
constexpr float nonExtinctedSolarMagnitude = -26.74;
using IndexType = uint16_t;
constexpr auto INDEX_GL_TYPE = GL_UNSIGNED_SHORT;

class AtmosphereLightweight
{
public:
    enum { DRAW_PARAM_SUN, DRAW_PARAM_MOON, DRAW_PARAM_COUNT };
#include "draw-params.inc"
    DrawParams drawParams[DRAW_PARAM_COUNT];
    struct Fader { float value = 1; float getInterstate() const { return value; } } fader;
    bool vividAtmosphereAllowed = false, overrideAverageLuminance = false;
    float averageLuminance = 0, lightPollutionLuminance = 0;
    std::vector<float> layerSolarElevations_{0.7f, 0.f, -0.7f};
    std::vector<float> layerNorms_{1.f, 2.f, 3.f}, layerValueMaxima_{1.f, 1.f, 1.f};
    std::vector<unsigned> layerIndexOffsetsInBuffer_{0, 12, 24, 36};
    std::unique_ptr<QOpenGLFramebufferObject> sunPrepFBO_, moonPrepFBO_;
    std::unique_ptr<QOpenGLShaderProgram> preparationShaderProgram_;
    QOpenGLBuffer indexBuffer_{QOpenGLBuffer::IndexBuffer}, vertices;
    QOpenGLVertexArrayObject vao;
    struct { int colorScale; } prepProgramUniformLocations_;
    int draws = 0, luminanceCalls = 0;
    float computeAverageLuminance(const StelCore*)
    {
        ++luminanceCalls;
        auto* gl = StelOpenGL::mainContext->functions();
        assert(!gl->glIsEnabled(GL_BLEND));
        gl->glViewport(0, 0, 128, 128);
        float result = 0;
        for (const auto& params : drawParams)
            result += params.relativeBrightness * params.eclipseFactor * params.fboColorScale;
        return result;
    }
    void bindVAO(unsigned layer)
    {
        ++draws;
        vao.bind();
        preparationShaderProgram_->setUniformValue("layerColor", QVector3D(0.1f + 0.2f * layer, 0.2f, 0.8f - 0.2f * layer));
    }
    void releaseVAO(int) { vao.release(); }
    void computeColor(StelCore*, double, const Planet&, const Planet&, const Planet*, const StelLocation&, float, float, float, bool);
    void computeDrawParams(const StelCore*, const Planet*, const Planet*, int, bool);
    AtmosphereLightweight()
    {
        sunPrepFBO_ = std::make_unique<QOpenGLFramebufferObject>(PREP_FBO_WIDTH, PREP_FBO_HEIGHT);
        moonPrepFBO_ = std::make_unique<QOpenGLFramebufferObject>(PREP_FBO_WIDTH, PREP_FBO_HEIGHT);
        assert(sunPrepFBO_->isValid() && moonPrepFBO_->isValid());
        preparationShaderProgram_ = std::make_unique<QOpenGLShaderProgram>();
        assert(preparationShaderProgram_->addShaderFromSourceCode(QOpenGLShader::Vertex,
            "#version 150\nin vec2 vertex; void main(){gl_Position=vec4(vertex,0,1);}"));
        assert(preparationShaderProgram_->addShaderFromSourceCode(QOpenGLShader::Fragment,
            "#version 150\nuniform vec3 layerColor; uniform float colorScale; out vec4 color; void main(){color=vec4(layerColor*colorScale,1);}"));
        preparationShaderProgram_->bindAttributeLocation("vertex", 0);
        assert(preparationShaderProgram_->link());
        preparationShaderProgram_->bind();
        prepProgramUniformLocations_.colorScale = preparationShaderProgram_->uniformLocation("colorScale");
        vao.create(); vao.bind(); vertices.create(); vertices.bind();
        const float points[] = {-1,-1, 1,-1, -1,1, 1,1};
        vertices.allocate(points, sizeof points);
        preparationShaderProgram_->setAttributeBuffer(0, GL_FLOAT, 0, 2);
        preparationShaderProgram_->enableAttributeArray(0);
        indexBuffer_.create(); indexBuffer_.bind();
        const IndexType indices[] = {0,1,2, 2,1,3, 0,1,2, 2,1,3, 0,1,2, 2,1,3};
        indexBuffer_.allocate(indices, sizeof indices);
        vao.release();
    }
};
#include "lightweight-preparation.inc"

std::vector<unsigned char> pixels(QOpenGLFramebufferObject& fbo)
{
    fbo.bind();
    std::vector<unsigned char> result(PREP_FBO_WIDTH * PREP_FBO_HEIGHT * 4);
    StelOpenGL::mainContext->functions()->glReadPixels(0, 0, PREP_FBO_WIDTH, PREP_FBO_HEIGHT, GL_RGBA, GL_UNSIGNED_BYTE, result.data());
    return result;
}

int main(int argc, char** argv)
{
    QGuiApplication app(argc, argv);
    QSurfaceFormat format;
    format.setVersion(3, 2); format.setProfile(QSurfaceFormat::CoreProfile);
    QOpenGLContext context; context.setFormat(format);
    if (!context.create()) return 2;
    QOffscreenSurface surface; surface.setFormat(context.format()); surface.create();
    if (!surface.isValid() || !context.makeCurrent(&surface)) return 2;
    StelOpenGL::mainContext = &context;
    auto* gl = context.functions(); gl->initializeOpenGLFunctions();
    AtmosphereLightweight atmosphere;
    StelCore core; StelLocation location; Planet sun, moon, earth;
    QOpenGLFramebufferObject original(32, 32);
    const auto run = [&](bool noScatter = false, bool moonPresent = true)
    {
        original.bind(); gl->glViewport(3, 4, 29, 27);
        gl->glEnable(GL_BLEND);
        gl->glBlendFunc(GL_SRC_ALPHA, GL_ONE);
        atmosphere.computeColor(&core, 0, earth, sun, moonPresent ? &moon : nullptr, location, 0, 0, 0, noScatter);
        GLint framebuffer = 0, viewport[4];
        gl->glGetIntegerv(GL_FRAMEBUFFER_BINDING, &framebuffer);
        gl->glGetIntegerv(GL_VIEWPORT, viewport);
        assert(GLuint(framebuffer) == original.handle());
        assert(viewport[0] == 3 && viewport[1] == 4 && viewport[2] == 29 && viewport[3] == 27);
        assert(gl->glGetError() == GL_NO_ERROR);
        assert(!gl->glIsEnabled(GL_BLEND));
        assert(std::isfinite(atmosphere.averageLuminance));
    };
    sun.position = moon.position = Vec3d(0., 0., 1.);
    for (auto* fbo : {atmosphere.sunPrepFBO_.get(), atmosphere.moonPrepFBO_.get()})
    {
        fbo->bind(); gl->glClearColor(1, 0, 1, 1); gl->glClear(GL_COLOR_BUFFER_BIT);
    }
    run();
    assert(atmosphere.draws == 2);
    assert(atmosphere.drawParams[0].layerAlpha == 0.f);
    auto first = pixels(*atmosphere.sunPrepFBO_);
    assert(std::abs(int(first[0]) - 26) <= 1 && std::abs(int(first[2]) - 204) <= 1);
    run(); assert(atmosphere.draws == 2 && atmosphere.luminanceCalls == 2);
    assert(pixels(*atmosphere.sunPrepFBO_) == first);
    sun.position = Vec3d(std::cos(0.3), 0., std::sin(0.3));
    run(); assert(atmosphere.draws == 4);
    first = pixels(*atmosphere.sunPrepFBO_);
    atmosphere.drawParams[0].prepCached = false;
    run(); assert(atmosphere.draws == 6);
    assert(pixels(*atmosphere.sunPrepFBO_) == first);
    sun.position = Vec3d(std::cos(0.31), 0., std::sin(0.31));
    run(); assert(atmosphere.draws == 8);
    assert(pixels(*atmosphere.sunPrepFBO_) != first);
    const auto oldDirection = atmosphere.drawParams[0].dir;
    sun.position = Vec3d(0., std::cos(0.31), std::sin(0.31));
    moon.magnitude -= 1;
    const float oldBrightness = atmosphere.drawParams[1].relativeBrightness;
    run(); assert(atmosphere.draws == 8);
    assert(atmosphere.drawParams[0].dir != oldDirection);
    assert(atmosphere.drawParams[1].relativeBrightness > oldBrightness);
    run(true); assert(atmosphere.draws == 8 && atmosphere.drawParams[0].relativeBrightness == 0);
    run(); assert(atmosphere.draws == 8 && atmosphere.drawParams[0].relativeBrightness == 1);
    sun.position = Vec3d(std::cos(-0.3), 0., std::sin(-0.3));
    run(); assert(atmosphere.draws == 10);
    atmosphere.overrideAverageLuminance = true;
    const int previousLuminanceCalls = atmosphere.luminanceCalls;
    run(); assert(atmosphere.luminanceCalls == previousLuminanceCalls);
    atmosphere.layerSolarElevations_ = {0.7f};
    atmosphere.drawParams[0].prepCached = atmosphere.drawParams[1].prepCached = false;
    run(); assert(atmosphere.draws == 12);
    assert(atmosphere.drawParams[0].layerAlpha == 0 && atmosphere.drawParams[1].layerAlpha == 0);
    run(); assert(atmosphere.draws == 12);
    atmosphere.layerSolarElevations_ = {0.7f, 0.f, -0.7f};
    atmosphere.overrideAverageLuminance = false;
    atmosphere.drawParams[0].prepCached = atmosphere.drawParams[1].prepCached = false;
    for (double elevation : {-1.57, -0.7, -0.3, 0., 0.3, 0.7, 1.57})
    {
        sun.position = Vec3d(std::cos(elevation), 0., std::sin(elevation));
        run();
        const auto expected = pixels(*atmosphere.sunPrepFBO_);
        const auto rendered = atmosphere.draws;
        run(); assert(atmosphere.draws == rendered);
        assert(pixels(*atmosphere.sunPrepFBO_) == expected);
        atmosphere.drawParams[0].prepCached = false;
        run(); assert(atmosphere.draws > rendered);
        assert(pixels(*atmosphere.sunPrepFBO_) == expected);
    }
    const auto beforeMoonChange = atmosphere.draws;
    moon.position = Vec3d(1., 0., 0.);
    run(); assert(atmosphere.draws == beforeMoonChange + 2);
    assert(atmosphere.drawParams[0].eclipseFactor == 1.f);
    run(false, false);
    assert(atmosphere.drawParams[1].dir == QVector3D(0, 0, -1));
    const auto withoutMoon = atmosphere.draws;
    run(false, false); assert(atmosphere.draws == withoutMoon);
    std::cout << "PASS: actual computeColor/computeDrawParams, real offscreen FBO pixels, exact reuse, first fill, alpha/layer invalidation, physics updates, single-layer mesh, framebuffer/viewport restoration\n";
}
