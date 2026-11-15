#include "VecMath.hpp"
#include <QGuiApplication>
#include <QOffscreenSurface>
#include <QOpenGLContext>
#include <QOpenGLFunctions>
#include <QOpenGLBuffer>
#include <QOpenGLFramebufferObject>
#include <QOpenGLShaderProgram>
#include <QOpenGLVertexArrayObject>
#include <QDebug>
#include <algorithm>
#include <array>
#include <cassert>
#include <iostream>
#include <vector>

struct Uploads
{
	int allocations = 0, writes = 0;
	std::size_t bytes = 0;
	bool operator==(const Uploads& other) const
	{
		return allocations == other.allocations && writes == other.writes && bytes == other.bytes;
	}
};

struct TrackedBuffer : QOpenGLBuffer
{
	using QOpenGLBuffer::QOpenGLBuffer;
	Uploads uploads;
	void allocate(int bytes) { ++uploads.allocations; QOpenGLBuffer::allocate(bytes); }
	void allocate(const void* data, int bytes)
	{
		++uploads.allocations;
		uploads.bytes += bytes;
		QOpenGLBuffer::allocate(data, bytes);
	}
	void write(int offset, const void* data, int bytes)
	{
		++uploads.writes;
		uploads.bytes += bytes;
		QOpenGLBuffer::write(offset, data, bytes);
	}
};

struct StelMainView
{
	struct Information { bool isCoreProfile = true; bool isGLES = false; };
	static StelMainView& getInstance() { static StelMainView view; return view; }
	Information getGLInformation() const { return {}; }
};

namespace StelOpenGL
{
	enum ShaderType { VERTEX_SHADER, FRAGMENT_SHADER };
	static QByteArray globalShaderPrefix(ShaderType type)
	{
		return type == VERTEX_SHADER
			? "#version 150\n#define ATTRIBUTE in\n#define VARYING out\n#define mediump\n"
			: "#version 150\n#define VARYING in\n#define mediump\nout vec4 outputColor;\n#define FRAG_COLOR outputColor\n";
	}
}

struct DrawSnapshot
{
	GLint program = 0, elements = 0, vertexBuffer = 0, colorBuffer = 0;
	GLint vertexEnabled = 0, colorEnabled = 0, depthFunction = 0, blendSrc = 0, blendDst = 0;
	void* vertexOffset = nullptr;
	void* colorOffset = nullptr;
	GLboolean depthMask = false, blend = false;
	std::array<GLboolean, 4> colorMask{};
	Uploads vertexUploads, indexUploads;
	GLenum mode = 0, indexType = 0;
	int count = 0;
	const void* indices = nullptr;
};

class StelPainter : public QOpenGLFunctions
{
public:
	enum DrawingMode { Triangles = GL_TRIANGLES, Lines = GL_LINES, LineStrip = GL_LINE_STRIP, LineLoop = GL_LINE_LOOP };
	struct ArrayDesc
	{
		int size = 0;
		GLenum type = GL_FLOAT;
		const void* pointer = nullptr;
		bool enabled = false;
		size_t vertexSizeInBytes() const;
	};
	struct ShaderVars
	{
		int vertex = -1, color = -1, projectionMatrix = -1, lineWidth = -1, viewportSize = -1;
		int texColor = -1, gamma = -1, saturation = -1, brightness = -1, contrast = -1, colorChannel = -1;
		int invertedColors = -1, premultiplyAlpha = -1, texCoord = -1, alpha = -1;
	};
	using TexturesShaderVars = ShaderVars;
	struct Projection { Mat4f matrix = Mat4f::identity(); const Mat4f& getProjectionMatrix() const { return matrix; } } projection;
	struct State
	{
		float lineWidth = 1.f;
		bool lineSmooth = false, depthMask = true, blend = false;
		GLenum blendSrc = GL_ONE, blendDst = GL_ZERO;
	} glState;
	ArrayDesc vertexArray, colorArray, texCoordArray, normalArray;
	TrackedBuffer vertexBuffer{QOpenGLBuffer::VertexBuffer}, indexBuffer{QOpenGLBuffer::IndexBuffer};
	TrackedBuffer* verticesVBO = &vertexBuffer;
	TrackedBuffer* indicesVBO = &indexBuffer;
	QOpenGLVertexArrayObject vertexArrayObject;
	QOpenGLVertexArrayObject* vao = &vertexArrayObject;
	QOpenGLShaderProgram colorShader;
	QOpenGLShaderProgram* colorShaderProgram = &colorShader;
	QOpenGLShaderProgram *basicShaderProgram = nullptr, *wideLineShaderProgram = nullptr, *colorfulWideLineShaderProgram = nullptr;
	QOpenGLShaderProgram *texturesShaderProgram = nullptr, *adjustedTexturesShaderProgram = nullptr, *texturesColorShaderProgram = nullptr;
	ShaderVars basicShaderVars, colorShaderVars, wideLineShaderVars, colorfulWideLineShaderVars;
	ShaderVars texturesShaderVars, adjustedTexturesShaderVars, texturesColorShaderVars;
	Vec4f currentColor{1.f};
	bool multisamplingEnabled = false, textureInvertedColors = false, texturePremultiplyAlpha = false;
	float textureGamma = 1.f, textureSaturation = 1.f, textureBrightness = 1.f, textureContrast = 1.f, saturation = 1.f, textureAlpha = 1.f;
	int textureColorChannel = 0;
	std::vector<DrawSnapshot> draws;
	int projections = 0;
	Projection* getProjector() { return &projection; }
	bool hasTextureDisplayAdjustment() const { return false; }
	ArrayDesc projectArray(const ArrayDesc& array, int, int, const unsigned short*) { ++projections; return array; }
	void drawFixedColorWideLinesAsQuads(const ArrayDesc&, int, int, const Mat4f&, DrawingMode) { assert(false); }
	void drawFromArray(DrawingMode, int, int = 0, bool = true, const unsigned short* = nullptr);
	void drawTrianglesWithDepthPrepass(int, const unsigned short*);
	void drawFromArrayImpl(DrawingMode, int, int, bool, const unsigned short*, bool);
	void setDepthMask(bool);
	void setBlending(bool, GLenum, GLenum);
	void glDrawElements(GLenum mode, GLsizei count, GLenum type, const void* indices)
	{
		DrawSnapshot snapshot;
		glGetIntegerv(GL_CURRENT_PROGRAM, &snapshot.program);
		glGetIntegerv(GL_ELEMENT_ARRAY_BUFFER_BINDING, &snapshot.elements);
		glGetVertexAttribiv(colorShaderVars.vertex, GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, &snapshot.vertexBuffer);
		glGetVertexAttribiv(colorShaderVars.color, GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, &snapshot.colorBuffer);
		glGetVertexAttribiv(colorShaderVars.vertex, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &snapshot.vertexEnabled);
		glGetVertexAttribiv(colorShaderVars.color, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &snapshot.colorEnabled);
		glGetVertexAttribPointerv(colorShaderVars.vertex, GL_VERTEX_ATTRIB_ARRAY_POINTER, &snapshot.vertexOffset);
		glGetVertexAttribPointerv(colorShaderVars.color, GL_VERTEX_ATTRIB_ARRAY_POINTER, &snapshot.colorOffset);
		glGetBooleanv(GL_DEPTH_WRITEMASK, &snapshot.depthMask);
		glGetBooleanv(GL_COLOR_WRITEMASK, snapshot.colorMask.data());
		glGetIntegerv(GL_DEPTH_FUNC, &snapshot.depthFunction);
		glGetIntegerv(GL_BLEND_SRC_RGB, &snapshot.blendSrc);
		glGetIntegerv(GL_BLEND_DST_RGB, &snapshot.blendDst);
		snapshot.blend = glIsEnabled(GL_BLEND);
		snapshot.vertexUploads = vertexBuffer.uploads;
		snapshot.indexUploads = indexBuffer.uploads;
		snapshot.mode = mode;
		snapshot.count = count;
		snapshot.indexType = type;
		snapshot.indices = indices;
		draws.push_back(snapshot);
		QOpenGLFunctions::glDrawElements(mode, count, type, indices);
	}
	void initialize()
	{
		initializeOpenGLFunctions();
		assert(vertexBuffer.create() && indexBuffer.create());
		vertexArrayObject.create();
		assert(vertexArrayObject.isCreated());
#include "painter-color-shaders.inc"
		assert(colorShader.addShaderFromSourceCode(QOpenGLShader::Vertex, vshaderInterpolatedColorSrc));
		assert(colorShader.addShaderFromSourceCode(QOpenGLShader::Fragment, fshaderInterpolatedColorSrc));
		assert(colorShader.link());
		colorShaderVars.vertex = colorShader.attributeLocation("vertex");
		colorShaderVars.color = colorShader.attributeLocation("color");
		colorShaderVars.projectionMatrix = colorShader.uniformLocation("projectionMatrix");
	}
};

#include "painter-depth-prepass.inc"

struct Pixels
{
	std::array<unsigned char, 64 * 64 * 4> color{};
	std::array<float, 64 * 64> depth{};
};

static Pixels render(StelPainter& painter, bool combined, const std::vector<unsigned short>& indices,
                     const std::array<GLboolean, 4>& colorMask, float alpha)
{
	const std::vector<Vec3f> vertices{{-0.8f,-0.8f,-0.4f}, {0.8f,-0.8f,-0.4f}, {0.f,0.8f,-0.4f},
		{-0.8f,-0.8f,0.4f}, {0.8f,-0.8f,0.4f}, {0.f,0.8f,0.4f}, {9.f,9.f,9.f}};
	const std::vector<Vec4f> colors{{1.f,0.f,0.f,alpha}, {1.f,0.f,0.f,alpha}, {1.f,0.f,0.f,alpha},
		{0.f,1.f,0.f,alpha}, {0.f,1.f,0.f,alpha}, {0.f,1.f,0.f,alpha}, {0.f,0.f,1.f,alpha}};
	painter.vertexArray = {3, GL_FLOAT, vertices.data(), true};
	painter.colorArray = {4, GL_FLOAT, colors.data(), true};
	painter.glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
	painter.setDepthMask(true);
	painter.glClearColor(0.1f, 0.2f, 0.3f, 0.4f);
	painter.glClearDepthf(1.f);
	painter.glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
	painter.glEnable(GL_DEPTH_TEST);
	painter.glDepthFunc(GL_LEQUAL);
	painter.glDisable(GL_CULL_FACE);
	painter.setBlending(false, GL_ONE, GL_ZERO);
	painter.setDepthMask(false);
	painter.glColorMask(colorMask[0], colorMask[1], colorMask[2], colorMask[3]);
	painter.vertexBuffer.uploads = {};
	painter.indexBuffer.uploads = {};
	painter.draws.clear();
	if (combined)
		painter.drawTrianglesWithDepthPrepass(indices.size(), indices.data());
	else
	{
		painter.setDepthMask(true);
		painter.glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
		painter.drawFromArray(StelPainter::Triangles, indices.size(), 0, false, indices.data());
		painter.glColorMask(colorMask[0], colorMask[1], colorMask[2], colorMask[3]);
		painter.setDepthMask(false);
		painter.setBlending(true, GL_SRC_ALPHA, GL_ONE);
		painter.drawFromArray(StelPainter::Triangles, indices.size(), 0, false, indices.data());
	}
	assert(painter.draws.size() == 2 && painter.projections == 0);
	const auto& depth = painter.draws[0];
	const auto& color = painter.draws[1];
	assert(depth.colorMask == (std::array<GLboolean, 4>{false, false, false, false}));
	assert(depth.depthMask && !color.depthMask);
	assert(color.colorMask == colorMask && color.blend && color.blendSrc == GL_SRC_ALPHA && color.blendDst == GL_ONE);
	assert(depth.depthFunction == GL_LEQUAL && color.depthFunction == GL_LEQUAL);
	assert(depth.program == color.program && depth.elements == color.elements);
	assert(depth.program == static_cast<GLint>(painter.colorShader.programId()));
	assert(depth.vertexBuffer == color.vertexBuffer && depth.colorBuffer == color.colorBuffer);
	assert(depth.vertexOffset == color.vertexOffset && depth.colorOffset == color.colorOffset);
	assert(depth.vertexEnabled && depth.colorEnabled && color.vertexEnabled && color.colorEnabled);
	assert(depth.indices == color.indices && depth.indexType == GL_UNSIGNED_SHORT && color.indexType == GL_UNSIGNED_SHORT);
	assert(depth.mode == GL_TRIANGLES && color.mode == GL_TRIANGLES && depth.count == color.count);
	const int factor = combined ? 1 : 2;
	const std::size_t copied = 1 + *std::max_element(indices.begin(), indices.end());
	assert(painter.vertexBuffer.uploads.allocations == factor && painter.vertexBuffer.uploads.writes == factor * 2);
	assert(painter.vertexBuffer.uploads.bytes == factor * copied * (sizeof(Vec3f) + sizeof(Vec4f)));
	assert(painter.indexBuffer.uploads.allocations == factor && painter.indexBuffer.uploads.bytes == factor * indices.size() * sizeof(unsigned short));
	if (combined)
	{
		assert(depth.vertexUploads == color.vertexUploads && depth.indexUploads == color.indexUploads);
	}
	std::array<GLboolean, 4> restoredMask{};
	painter.glGetBooleanv(GL_COLOR_WRITEMASK, restoredMask.data());
	assert(restoredMask == colorMask && !painter.glState.depthMask && painter.glState.blend);
	Pixels result;
	painter.glReadPixels(0, 0, 64, 64, GL_RGBA, GL_UNSIGNED_BYTE, result.color.data());
	painter.glReadPixels(0, 0, 64, 64, GL_DEPTH_COMPONENT, GL_FLOAT, result.depth.data());
	assert(painter.glGetError() == GL_NO_ERROR);
	return result;
}

int main(int argc, char** argv)
{
	QGuiApplication application(argc, argv);
	QSurfaceFormat format;
	format.setVersion(3, 2);
	format.setProfile(QSurfaceFormat::CoreProfile);
	format.setDepthBufferSize(24);
	QOpenGLContext context;
	context.setFormat(format);
	if (!context.create()) { std::cerr << "No desktop GL context available\n"; return 2; }
	QOffscreenSurface surface;
	surface.setFormat(context.format());
	surface.create();
	if (!surface.isValid() || !context.makeCurrent(&surface)) { std::cerr << "No offscreen GL surface available\n"; return 2; }
	StelPainter painter;
	painter.initialize();
	QOpenGLFramebufferObject framebuffer(64, 64, QOpenGLFramebufferObject::CombinedDepthStencil);
	assert(framebuffer.isValid() && framebuffer.bind());
	painter.glViewport(0, 0, 64, 64);
	const std::vector<std::vector<unsigned short>> meshes{{0,1,2,3,4,5}, {3,4,5,0,1,2}, {3,4,5}, {0,1,2}};
	const std::vector<std::array<GLboolean, 4>> masks{{true,true,true,true}, {true,false,true,false}, {false,false,false,false}};
	for (const auto& indices : meshes)
		for (const auto& mask : masks)
			for (float alpha : {0.f, 0.25f, 1.f})
			{
				const auto legacy = render(painter, false, indices, mask, alpha);
				const auto actual = render(painter, true, indices, mask, alpha);
				assert(actual.color == legacy.color && actual.depth == legacy.depth);
				const float expectedDepth = indices.front() == 3 && indices.size() == 3 ? 0.7f : 0.3f;
				assert(std::abs(actual.depth[32 * 64 + 32] - expectedDepth) < 1.e-5f);
			}
	painter.draws.clear();
	painter.vertexBuffer.uploads = {};
	painter.indexBuffer.uploads = {};
	painter.drawTrianglesWithDepthPrepass(0, nullptr);
	painter.drawTrianglesWithDepthPrepass(-1, nullptr);
	painter.drawFromArray(StelPainter::Triangles, 0, 0, false, nullptr);
	assert(painter.draws.empty() && painter.vertexBuffer.uploads.allocations == 0 && painter.indexBuffer.uploads.allocations == 0);
	const Vec3f vertices[]{{-0.8f,-0.8f,0.f}, {0.8f,-0.8f,0.f}, {0.f,0.8f,0.f}};
	const Vec4f colors[]{Vec4f(1.f), Vec4f(1.f), Vec4f(1.f)};
	const unsigned short offsetIndices[]{65535, 0, 1, 2};
	painter.vertexArray = {3, GL_FLOAT, vertices, true};
	painter.colorArray = {4, GL_FLOAT, colors, true};
	painter.setDepthMask(true);
	painter.setBlending(false, GL_ONE, GL_ZERO);
	painter.drawFromArray(StelPainter::Triangles, 3, 1, false, offsetIndices);
	assert(painter.draws.size() == 1 && painter.draws[0].depthMask && !painter.draws[0].blend);
	assert(painter.vertexBuffer.uploads.bytes == 3 * (sizeof(Vec3f) + sizeof(Vec4f)));
	painter.drawFromArray(StelPainter::Triangles, 3, 0, true, nullptr);
	assert(painter.projections == 1 && painter.draws.size() == 1);
	assert(painter.glGetError() == GL_NO_ERROR);
	std::cout << "Offscreen GL: 36 color/depth equivalence cases, single uploads, masks, attributes, empty input and ordinary draw passed\n";
}
