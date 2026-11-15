#include "VecMath.hpp"
#include <QGuiApplication>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QOpenGLFunctions_3_3_Core>
#include <QOpenGLShaderProgram>
#include <QOpenGLFramebufferObject>
#include <QOpenGLVertexArrayObject>
#include <QDebug>
#include <array>
#include <cassert>
#include <chrono>
#include <deque>
#include <iostream>
#include <memory>
#include <numeric>
#include <vector>

#define GL(expression) do { expression; while (testGL().glGetError() != GL_NO_ERROR) {} } while (false)

class TestGL : public QOpenGLExtraFunctions
{
public:
	GLenum forcedWait = 0;
	bool failMap = false, failUnmap = false, failRead = false;
	int maps = 0;
	GLenum glClientWaitSync(GLsync sync, GLbitfield flags, GLuint64 timeout)
	{
		assert(flags == 0 && timeout == 0);
		return forcedWait ? forcedWait : QOpenGLExtraFunctions::glClientWaitSync(sync, flags, timeout);
	}
	void* glMapBufferRange(GLenum target, GLintptr offset, GLsizeiptr size, GLbitfield access)
	{
		++maps;
		return failMap ? nullptr : QOpenGLExtraFunctions::glMapBufferRange(target, offset, size, access);
	}
	GLboolean glUnmapBuffer(GLenum target)
	{
		const auto result = QOpenGLExtraFunctions::glUnmapBuffer(target);
		return failUnmap ? GL_FALSE : result;
	}
	void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height, GLenum format, GLenum type, void* data)
	{
		QOpenGLExtraFunctions::glReadPixels(x, y, width, height, failRead ? GL_NONE : format, type, data);
	}
};

static TestGL& testGL() { static TestGL functions; return functions; }
struct StelMainView
{
	struct Information { bool isGLES = true; };
	static StelMainView& getInstance() { static StelMainView view; return view; }
	Information getGLInformation() const { return {}; }
};
namespace StelUtils
{
	static int getSmallerPowerOfTwo(int value) { int result = 1; while (result <= value / 2) result *= 2; return result; }
}
namespace StelOpenGL
{
	using HighGraphicsFunctions = QOpenGLFunctions_3_3_Core;
	enum ShaderType { VERTEX_SHADER, FRAGMENT_SHADER };
	static QByteArray globalShaderPrefix(ShaderType type)
	{
		return type == VERTEX_SHADER
			? "#version 150\n#define ATTRIBUTE in\n#define VARYING out\n#define mediump\n#define highp\n"
			: "#version 150\n#define VARYING in\n#define mediump\n#define highp\n#define texture2D texture\nout vec4 outputColor;\n#define FRAG_COLOR outputColor\n";
	}
}

#include "texture-average-source.inc"

struct PackState
{
	GLint buffer, alignment, rowLength, skipRows, skipPixels, swapBytes, readFBO, drawFBO;
	std::array<GLint, 4> viewport;
	static PackState capture()
	{
		auto& gl = testGL();
		PackState state;
		gl.glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &state.buffer);
		gl.glGetIntegerv(GL_PACK_ALIGNMENT, &state.alignment);
		gl.glGetIntegerv(GL_PACK_ROW_LENGTH, &state.rowLength);
		gl.glGetIntegerv(GL_PACK_SKIP_ROWS, &state.skipRows);
		gl.glGetIntegerv(GL_PACK_SKIP_PIXELS, &state.skipPixels);
		gl.glGetIntegerv(GL_PACK_SWAP_BYTES, &state.swapBytes);
		gl.glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &state.readFBO);
		gl.glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &state.drawFBO);
		gl.glGetIntegerv(GL_VIEWPORT, state.viewport.data());
		return state;
	}
	bool operator==(const PackState& other) const
	{
		return buffer == other.buffer && alignment == other.alignment && rowLength == other.rowLength
			&& skipRows == other.skipRows && skipPixels == other.skipPixels && swapBytes == other.swapBytes
			&& readFBO == other.readFBO && drawFBO == other.drawFBO && viewport == other.viewport;
	}
};

static void fillTexture(GLuint texture, const Vec4f& value)
{
	std::vector<Vec4f> pixels(16 * 16, value);
	auto& gl = testGL();
	gl.glBindTexture(GL_TEXTURE_2D, texture);
	gl.glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 16, 16, GL_RGBA, GL_FLOAT, pixels.data());
}

static void assertNear(const Vec4f& actual, const Vec4f& expected, float tolerance)
{
	for (int component = 0; component < 4; ++component)
		assert(std::isfinite(actual[component]) && std::abs(actual[component] - expected[component]) <= tolerance);
}

static void testReadbacks(bool floating)
{
	auto& gl = testGL();
	QOpenGLFramebufferObjectFormat format;
	format.setInternalTextureFormat(floating ? GL_RGBA32F : GL_RGBA8);
	QOpenGLFramebufferObject input(16, 16, format), readTarget(2, 2), drawTarget(2, 2);
	assert(input.isValid());
	TextureAverageComputer computer(nullptr, 16, 16, floating ? GL_RGBA32F : GL_RGBA8, floating);
	GLuint external;
	gl.glGenBuffers(1, &external);
	gl.glBindBuffer(GL_PIXEL_PACK_BUFFER, external);
	gl.glBufferData(GL_PIXEL_PACK_BUFFER, 4096, nullptr, GL_STREAM_READ);
	gl.glPixelStorei(GL_PACK_ALIGNMENT, 8);
	gl.glPixelStorei(GL_PACK_ROW_LENGTH, 7);
	gl.glPixelStorei(GL_PACK_SKIP_ROWS, 2);
	gl.glPixelStorei(GL_PACK_SKIP_PIXELS, 3);
	gl.glPixelStorei(GL_PACK_SWAP_BYTES, 1);
	gl.glBindFramebuffer(GL_READ_FRAMEBUFFER, readTarget.handle());
	gl.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, drawTarget.handle());
	gl.glViewport(3, 5, 13, 17);
	const auto state = PackState::capture();
	const std::array<Vec4f, 3> values{Vec4f(.2f,.4f,.6f,1.f), Vec4f(.8f,.2f,.4f,1.f), Vec4f(.4f,.6f,.8f,1.f)};
	for (unsigned index = 0; index < 3; ++index)
	{
		fillTexture(input.texture(), values[index]);
		assert(computer.enqueueTextureAverageSimple(input.texture(), 16, 16, index + 10));
		assert(PackState::capture() == state);
	}
	assert(!computer.enqueueTextureAverageSimple(input.texture(), 16, 16, 99));
	TextureAverageComputer::AsyncResult result;
	gl.forcedWait = GL_TIMEOUT_EXPIRED;
	const int previousMaps = gl.maps;
	assert(!computer.pollTextureAverage(result) && gl.maps == previousMaps);
	assert(PackState::capture() == state);
	gl.forcedWait = 0;
	gl.glFinish();
	for (unsigned index = 0; index < 3; ++index)
	{
		assert(computer.pollTextureAverage(result) && result.token == index + 10);
		assertNear(result.value, values[index], floating ? 1.e-6f : 1.f / 255.f);
		assert(PackState::capture() == state);
	}
	assert(!computer.pollTextureAverage(result));
	assertNear(computer.getTextureAverageSimple(input.texture(), 16, 16), values[2], floating ? 1.e-6f : 1.f / 255.f);
	assert(PackState::capture() == state);
	std::vector<Vec4f> pixels;
	for (int index = 0; index < 256; ++index)
		pixels.emplace_back((index % 16) / 15.f, (index / 16) / 15.f, (index % 2) * 1.f, 1.f);
	gl.glBindTexture(GL_TEXTURE_2D, input.texture());
	gl.glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, 16, 16, GL_RGBA, GL_FLOAT, pixels.data());
	const auto expected = computer.getTextureAverageSimple(input.texture(), 16, 16);
	for (std::uint64_t token = 20; token < 26; ++token)
	{
		assert(computer.enqueueTextureAverageSimple(input.texture(), 16, 16, token));
		gl.glFinish();
		assert(computer.pollTextureAverage(result) && result.token == token);
		assertNear(result.value, expected, 0.f);
		assert(PackState::capture() == state);
	}
	fillTexture(input.texture(), values[2]);
	assert(computer.enqueueTextureAverageSimple(input.texture(), 16, 16, 100));
	computer.resetAsyncReadback();
	assert(!computer.pollTextureAverage(result) && PackState::capture() == state);
	assert(computer.enqueueTextureAverageSimple(input.texture(), 16, 16, 101));
	gl.forcedWait = GL_WAIT_FAILED;
	assert(!computer.pollTextureAverage(result) && !computer.supportsAsyncReadback());
	gl.forcedWait = 0;
	computer.resetAsyncReadback();
	assertNear(computer.getTextureAverageSimple(input.texture(), 16, 16), values[2], floating ? 1.e-6f : 1.f / 255.f);
	assert(PackState::capture() == state);
	gl.glBindBuffer(GL_PIXEL_PACK_BUFFER, 0);
	gl.glDeleteBuffers(1, &external);
	gl.glPixelStorei(GL_PACK_ALIGNMENT, 4);
	gl.glPixelStorei(GL_PACK_ROW_LENGTH, 0);
	gl.glPixelStorei(GL_PACK_SKIP_ROWS, 0);
	gl.glPixelStorei(GL_PACK_SKIP_PIXELS, 0);
	gl.glPixelStorei(GL_PACK_SWAP_BYTES, 0);
	assert(gl.glGetError() == GL_NO_ERROR);
}

static void testMappingFailures()
{
	auto& gl = testGL();
	QOpenGLFramebufferObject input(16, 16);
	fillTexture(input.texture(), Vec4f(.4f));
	for (bool unmap : {false, true})
	{
		TextureAverageComputer computer(nullptr, 16, 16, GL_RGBA8, false);
		assert(computer.enqueueTextureAverageSimple(input.texture(), 16, 16, 1));
		gl.glFinish();
		gl.failMap = !unmap;
		gl.failUnmap = unmap;
		TextureAverageComputer::AsyncResult result;
		assert(!computer.pollTextureAverage(result) && !computer.supportsAsyncReadback());
		gl.failMap = gl.failUnmap = false;
		computer.resetAsyncReadback();
		assertNear(computer.getTextureAverageSimple(input.texture(), 16, 16), Vec4f(.4f), 1.f / 255.f);
	}
	TextureAverageComputer failedRead(nullptr, 16, 16, GL_RGBA8, false);
	gl.failRead = true;
	assert(!failedRead.enqueueTextureAverageSimple(input.texture(), 16, 16, 1));
	assert(!failedRead.supportsAsyncReadback());
	gl.failRead = false;
	failedRead.resetAsyncReadback();
	assertNear(failedRead.getTextureAverageSimple(input.texture(), 16, 16), Vec4f(.4f), 1.f / 255.f);
}

struct TestLocation
{
	float latitude = 0.f, longitude = 0.f;
	int altitude = 0;
	QString planetName = "Earth";
	float getLatitude() const { return latitude; }
	float getLongitude() const { return longitude; }
};
struct TestCore
{
	double jd = 2451545.;
	double rate = 1. / 86400., syncJD = 2451545.;
	qint64 syncMilliseconds = 1000;
	TestLocation location;
	double getJD() const { return jd; }
	double getTimeRate() const { return rate; }
	double getJDOfLastJDUpdate() const { return syncJD; }
	qint64 getMilliSecondsOfLastJDUpdate() const { return syncMilliseconds; }
	const TestLocation& getCurrentLocation() const { return location; }
};
struct TestProjection
{
	float fov = 60.f;
	Vec3d direction{0., 0., 1.};
	bool valid = true;
	float getFov() const { return fov; }
	Vec2d getViewportCenter() const { return Vec2d(64., 64.); }
	bool unProject(double, double, Vec3d& result) const { result = direction; return valid; }
};
struct FakeAverage
{
	bool supported = true, failEnqueue = false;
	int syncCalls = 0;
	Vec4f value{.2f,.4f,0.f,1.f};
	std::deque<TextureAverageComputer::AsyncResult> ready;
	std::vector<std::uint64_t> queued;
	bool supportsAsyncReadback() const { return supported; }
	bool pollTextureAverage(TextureAverageComputer::AsyncResult& result)
	{
		if (ready.empty()) return false;
		result = ready.front(); ready.pop_front(); return true;
	}
	bool enqueueTextureAverageSimple(GLuint, int, int, std::uint64_t token)
	{
		if (failEnqueue) { supported = false; return false; }
		queued.push_back(token); return true;
	}
	void resetAsyncReadback() { ready.clear(); queued.clear(); }
	Vec4f getTextureAverageSimple(GLuint, int, int) { ++syncCalls; return value; }
};

class LightweightHarness
{
public:
	static constexpr int DRAW_PARAM_COUNT = 2, LUM_PROBE_FBO_WIDTH = 128, LUM_PROBE_FBO_HEIGHT = 128;
	bool testGLES = true;
	std::chrono::steady_clock::time_point testNow{};
	TestProjection projection;
	TestProjection* prj = &projection;
	struct Parameters
	{
		float relativeBrightness = 1.f, eclipseFactor = 1.f, fboColorScale = 1.f, layerAlpha = 0.f;
		unsigned layerToDrawA = 0, layerToDrawB = 0;
		QVector3D dir{0.f, 0.f, 1.f};
	};
	Parameters drawParams[2];
	std::vector<float> layerValueMaxima_{1.f};
	std::unique_ptr<FakeAverage> textureAverager_{new FakeAverage};
	struct FBO { GLuint texture() { return 1; } };
	std::unique_ptr<FBO> luminanceProbeFBO_{new FBO};
#include "luminance-fields.inc"
#define __OHOS__
#include "luminance-tail.inc"
#undef __OHOS__
};

static void testSampleWeightsAndFallback()
{
	TestCore core;
	LightweightHarness model;
	auto& helper = *model.textureAverager_;
	assert(std::abs(model.computeAverageLuminance(&core) - .6f) < 1.e-6f);
	assert(helper.syncCalls == 1);
	model.computeAverageLuminance(&core);
	assert(helper.queued.back() == 2);
	model.drawParams[0].relativeBrightness = 1.1f;
	helper.ready.push_back({Vec4f(.8f,.1f,0.f,1.f), 2});
	assert(std::abs(model.computeAverageLuminance(&core) - .9f) < 1.e-6f);
	assert(helper.syncCalls == 1);
	model.computeAverageLuminance(&core);
	helper.ready.push_back({Vec4f(.5f,.2f,0.f,1.f), 4});
	helper.ready.push_back({Vec4f(9.f), 3});
	assert(std::abs(model.computeAverageLuminance(&core) - .75f) < 1.e-6f);
	core.jd += .5;
	assert(std::abs(model.computeAverageLuminance(&core) - .62f) < 1.e-6f && helper.syncCalls == 2);
	core.location.longitude = 90;
	model.computeAverageLuminance(&core); assert(helper.syncCalls == 3);
	core.location.planetName = "Mars";
	model.computeAverageLuminance(&core); assert(helper.syncCalls == 4);
	model.drawParams[0].relativeBrightness = model.drawParams[1].relativeBrightness = 0;
	assert(model.computeAverageLuminance(&core) == 0.f && helper.syncCalls == 5);
	helper.value = Vec4f(NAN);
	core.jd += .5;
	assert(model.computeAverageLuminance(&core) == 0.f && !model.completedMeanLuminanceValid_);
	helper.value = Vec4f(.4f);
	model.computeAverageLuminance(&core);
	model.completedLuminanceSample_.sampledAt -= std::chrono::seconds(1);
	int count = helper.syncCalls;
	model.computeAverageLuminance(&core); assert(helper.syncCalls == count + 1);
	for (int frame = 0; frame < 4; ++frame) model.computeAverageLuminance(&core);
	assert(helper.syncCalls == count + 2);
	helper.failEnqueue = true;
	model.computeAverageLuminance(&core); assert(helper.syncCalls == count + 3);
	model.computeAverageLuminance(&core); assert(helper.syncCalls == count + 4);
	LightweightHarness desktop;
	desktop.testGLES = false;
	desktop.computeAverageLuminance(&core); desktop.computeAverageLuminance(&core);
	assert(desktop.textureAverager_->syncCalls == 2 && desktop.textureAverager_->queued.empty());
}

static void testViewChanges()
{
	TestCore core;
	LightweightHarness model;
	auto& helper = *model.textureAverager_;
	model.computeAverageLuminance(&core);
	model.computeAverageLuminance(&core);
	const double smallAngle = 2. * M_PI / 180.;
	model.projection.direction = Vec3d(std::sin(smallAngle), 0., std::cos(smallAngle));
	helper.ready.push_back({Vec4f(.4f,.2f,0.f,1.f), 2});
	model.computeAverageLuminance(&core);
	assert(helper.syncCalls == 1 && !helper.queued.empty());
	model.projection.direction = Vec3d(1., 0., 0.);
	helper.ready.push_back({Vec4f(9.f), 3});
	assert(std::abs(model.computeAverageLuminance(&core) - .6f) < 1.e-6f);
	assert(helper.syncCalls == 2 && helper.queued.empty() && model.pendingLuminanceSamples_.empty());
	model.projection.fov = 80.f;
	model.computeAverageLuminance(&core);
	assert(helper.syncCalls == 3);
	model.projection.fov = 78.f;
	model.computeAverageLuminance(&core);
	assert(helper.syncCalls == 3);
	model.projection.fov = 2.f;
	model.projection.direction = Vec3d(0., 0., 1.);
	model.computeAverageLuminance(&core);
	assert(helper.syncCalls == 4);
	const double narrowAngle = 0.6 * M_PI / 180.;
	model.projection.direction = Vec3d(std::sin(narrowAngle), 0., std::cos(narrowAngle));
	model.computeAverageLuminance(&core);
	assert(helper.syncCalls == 5);
	model.projection.valid = false;
	model.computeAverageLuminance(&core);
	assert(helper.syncCalls == 6);
	model.projection.valid = true;
	model.projection.fov = NAN;
	model.computeAverageLuminance(&core);
	assert(helper.syncCalls == 7);
}

static void testContinuousFastTime()
{
	for (double multiplier : {3600., -3600., 0., 1.})
	{
		TestCore core;
		core.rate = multiplier / 86400.;
		LightweightHarness model;
		auto& helper = *model.textureAverager_;
		model.computeAverageLuminance(&core);
		for (int frame = 1; frame <= 120; ++frame)
		{
			model.testNow += std::chrono::milliseconds(55);
			core.jd += core.rate * .055;
			const double angle = multiplier * frame * .055 * (2. * M_PI / 86400.);
			for (int index = 0; index < 2; ++index)
			{
				model.drawParams[index].dir = QVector3D(std::sin(angle), 0., std::cos(angle));
				model.drawParams[index].layerAlpha = .1f * std::sin(frame * .01f);
			}
			if (!helper.queued.empty()) helper.ready.push_back({helper.value, helper.queued.back()});
			assert(std::abs(model.computeAverageLuminance(&core) - .6f) < 1.e-6f);
			assert(helper.syncCalls == 1);
		}
		assert(helper.queued.size() == 120);
		++core.syncMilliseconds;
		model.computeAverageLuminance(&core);
		assert(helper.syncCalls == 2 && helper.queued.empty());
		model.computeAverageLuminance(&core);
		assert(helper.syncCalls == 2 && !helper.queued.empty());
		core.rate = -core.rate + 1. / 86400.;
		model.computeAverageLuminance(&core);
		assert(helper.syncCalls == 3 && helper.queued.empty());
	}
	std::cout << "Continuous time: 120 frames each at +3600x/-3600x/paused/realtime; only initial sync, explicit reset and rate change refresh passed\n";
}

static void testPhysicalDiscontinuities()
{
	const auto reject = [](auto change)
	{
		TestCore core;
		LightweightHarness model;
		model.layerValueMaxima_.push_back(1.f);
		auto& helper = *model.textureAverager_;
		model.computeAverageLuminance(&core);
		model.computeAverageLuminance(&core);
		helper.ready.push_back({Vec4f(9.f), 2});
		change(core, model);
		const float expected = helper.value[0] * model.drawParams[0].eclipseFactor
			+ helper.value[1] * model.drawParams[1].eclipseFactor;
		assert(std::abs(model.computeAverageLuminance(&core) - expected) < 1.e-6f);
		assert(helper.syncCalls == 2 && helper.queued.empty() && model.pendingLuminanceSamples_.empty());
	};
	reject([](auto& core, auto&) { core.syncJD += 1. / 86400.; core.jd += 1. / 86400.; });
	reject([](auto&, auto& model) { model.testNow += std::chrono::milliseconds(250); });
	reject([](auto&, auto& model) { model.testNow -= std::chrono::milliseconds(1); });
	reject([](auto& core, auto&) { core.jd += 10. / 86400.; });
	reject([](auto& core, auto&) { core.jd = NAN; });
	reject([](auto& core, auto&) { core.rate = NAN; });
	for (int index = 0; index < 2; ++index)
	{
		reject([index](auto&, auto& model) {
			const double angle = 1.1 * M_PI / 180.;
			model.drawParams[index].dir = QVector3D(std::sin(angle), 0., std::cos(angle));
		});
		reject([index](auto&, auto& model) { model.drawParams[index].dir = QVector3D(NAN, 0.f, 1.f); });
		reject([index](auto&, auto& model) { model.drawParams[index].dir = QVector3D(0.f, 0.f, 0.f); });
		reject([index](auto&, auto& model) { model.drawParams[index].layerToDrawA = 1; });
		reject([index](auto&, auto& model) { model.drawParams[index].layerToDrawB = 1; });
		reject([index](auto&, auto& model) { model.drawParams[index].layerAlpha = .26f; });
		reject([index](auto&, auto& model) { model.drawParams[index].layerAlpha = NAN; });
		reject([index](auto&, auto& model) { model.drawParams[index].eclipseFactor = .2f; });
	}
	TestCore core;
	core.rate = 20.;
	LightweightHarness model;
	model.computeAverageLuminance(&core);
	core.jd += 1.;
	model.testNow += std::chrono::milliseconds(50);
	model.computeAverageLuminance(&core);
	assert(model.textureAverager_->syncCalls == 2);
	std::cout << "Physical guards: explicit small jump, real age, elapsed mismatch, invalid data, sun/moon direction, layer/blend/eclipse and whole-day alias rejected\n";
}

static void testProbePoles()
{
	auto& gl = testGL();
	QOpenGLFramebufferObjectFormat format;
	format.setInternalTextureFormat(GL_RGBA32F);
	QOpenGLFramebufferObject target(2, 2, format), texture(16, 16, format);
	fillTexture(texture.texture(), Vec4f(.1f,.2f,.5f,1.f));
	QOpenGLShaderProgram shader;
	assert(shader.addShaderFromSourceCode(QOpenGLShader::Vertex,
		"#version 150\nout vec3 ndcPos; void main(){ vec2 p=vec2((gl_VertexID&1)*2-1,(gl_VertexID/2)*2-1); ndcPos=vec3(p,0); gl_Position=vec4(p,0,1); }"));
#include "luminance-probe.inc"
	const QByteArray unproject = "uniform vec3 testDirection; vec3 unProject(float x,float y,out bool ok) { ok=true; return testDirection; }\n";
	assert(shader.addShaderFromSourceCode(QOpenGLShader::Fragment,
		StelOpenGL::globalShaderPrefix(StelOpenGL::FRAGMENT_SHADER) + unproject + luminanceProbeFragSrc));
	assert(shader.link() && shader.bind());
	shader.setUniformValue("projectionMatrixInverse", QMatrix4x4());
	shader.setUniformValue("atmoTex", 0);
	QOpenGLVertexArrayObject vao; vao.create(); vao.bind();
	target.bind(); gl.glViewport(0, 0, 2, 2);
	gl.glActiveTexture(GL_TEXTURE0); gl.glBindTexture(GL_TEXTURE_2D, texture.texture());
	gl.glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
	for (auto direction : {QVector3D(0,0,1), QVector3D(0,0,-1), QVector3D(1,0,0)})
		for (auto sun : {QVector3D(0,0,1), QVector3D(0,0,-1), QVector3D(1,0,0)})
			for (bool moon : {false, true})
			{
				shader.setUniformValue("testDirection", direction);
				shader.setUniformValue("sunDir", sun);
				shader.setUniformValue("isMoon", moon);
				gl.glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
				Vec4f pixel;
				gl.glReadPixels(0, 0, 1, 1, GL_RGBA, GL_FLOAT, &pixel[0]);
				assertNear(pixel, moon ? Vec4f(0,.25f,0,1) : Vec4f(.25f,0,0,1), 1.e-6f);
			}
	assert(gl.glGetError() == GL_NO_ERROR);
}

int main(int argc, char** argv)
{
	QGuiApplication application(argc, argv);
	QSurfaceFormat format; format.setVersion(3, 2); format.setProfile(QSurfaceFormat::CoreProfile);
	QOpenGLContext context; context.setFormat(format);
	assert(context.create());
	QOffscreenSurface surface; surface.setFormat(context.format()); surface.create();
	assert(context.makeCurrent(&surface)); testGL().initializeOpenGLFunctions();
	testReadbacks(false); testReadbacks(true);
	testMappingFailures(); testSampleWeightsAndFallback(); testViewChanges(); testProbePoles();
	testContinuousFastTime(); testPhysicalDiscontinuities();
	std::cout << "Async average: real PBO byte/float FIFO, ring-full, timeout/failures under draining GL macros, pack/FBO restore; extracted Lightweight weights/camera/FOV/discontinuities/fallback; 18 probe-pole GLSL cases passed\n";
}
