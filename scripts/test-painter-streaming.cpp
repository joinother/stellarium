#include "VecMath.hpp"
#include <algorithm>
#include <cassert>
#include <cstring>
#include <iostream>
#include <vector>

using GLint = int;
constexpr int GL_FLOAT = 1;
constexpr int GL_VIEWPORT = 2;
constexpr int GL_TRIANGLES = 3;

struct BufferCapture
{
	std::vector<Vec4f> vertices;
	void bind() {}
	void release() {}
	void allocate(const void* data, std::size_t bytes)
	{
		assert(bytes % sizeof(Vec4f) == 0);
		vertices.resize(bytes / sizeof(Vec4f));
		std::memcpy(vertices.data(), data, bytes);
	}
};

struct BindingCapture
{
	void bind() {}
	void release() {}
};

struct ShaderCapture : BindingCapture
{
	QVector4D color;
	QMatrix4x4 projection;
	void setAttributeBuffer(int, int, int offset, int components)
	{
		assert(offset == 0 && components == 4);
	}
	void enableAttributeArray(int) {}
	void setUniformValue(int, const QVector4D& value) { color = value; }
	void setUniformValue(int, const QMatrix4x4& value) { projection = value; }
};

static BufferCapture bufferCapture;
static BindingCapture bindingCapture;
static ShaderCapture shaderCapture;
static auto* verticesVBO = &bufferCapture;
static auto* vao = &bindingCapture;
static auto* basicShaderProgram = &shaderCapture;
static const struct { int vertex = 1, projectionMatrix = 2, color = 3; } basicShaderVars;
static int submittedVertices = 0;
static int submissions = 0;

static void glGetIntegerv(int parameter, int* viewport)
{
	assert(parameter == GL_VIEWPORT);
	const int values[] = {13, 17, 1000, 700};
	std::copy(values, values + 4, viewport);
}

static void glDrawArrays(int mode, int offset, int count)
{
	assert(mode == GL_TRIANGLES && offset == 0);
	assert(static_cast<std::size_t>(count) == bufferCapture.vertices.size());
	submittedVertices = count;
	++submissions;
}

class StelPainter
{
public:
	enum DrawingMode { Lines, LineStrip, LineLoop };
	struct ArrayDesc { int type = GL_FLOAT; int size = 4; const void* pointer = nullptr; };
	struct { float lineWidth = 3.f; } glState;
	Vec4f currentColor{0.2f, 0.4f, 0.7f, 0.35f};
	void drawFixedColorWideLinesAsQuads(const ArrayDesc&, int, int, const Mat4f&, DrawingMode);
	void drawLegacyWideLines(const ArrayDesc&, int, int, const Mat4f&, DrawingMode);
};

#include "wide-lines-current.inc"
#include "wide-lines-legacy.inc"

static bool equal(const Vec4f& first, const Vec4f& second)
{
	return std::memcmp(first.v, second.v, sizeof(first.v)) == 0;
}

static bool near(float first, float second)
{
	return std::abs(first - second) < 2.e-5f;
}

static void testModesAgainstLegacy()
{
	StelPainter painter;
	for (const auto mode : {StelPainter::Lines, StelPainter::LineStrip, StelPainter::LineLoop})
		for (const int count : {0, 1, 2, 3, 4, 5, 17, 256})
			for (const int components : {2, 3, 4})
				for (const int offset : {0, 2})
				{
					std::vector<float> input;
					for (int index = 0; index < count + offset; ++index)
					{
						const float angle = index * 0.37f;
						const float radius = 0.3f + index * 0.001f;
						const float values[] = {radius * std::cos(angle), radius * std::sin(angle), index * 0.001f, 1.f + index * 0.01f};
						input.insert(input.end(), values, values + components);
					}
					const StelPainter::ArrayDesc array{GL_FLOAT, components, input.data()};
					const auto projection = Mat4f::scaling(Vec3f(0.9f, 0.7f, 0.5f));
					submissions = 0;
					bufferCapture.vertices.clear();
					painter.drawFixedColorWideLinesAsQuads(array, count, offset, projection, mode);
					const auto actual = bufferCapture.vertices;
					const int segments = count < 2 ? 0 : mode == StelPainter::Lines ? count / 2 : mode == StelPainter::LineLoop ? count : count - 1;
					assert(actual.size() == static_cast<std::size_t>(segments * 6));
					assert(submissions == (count < 2 ? 0 : 1));
					if (count < 2) continue;
					assert(submittedVertices == segments * 6);
					assert(shaderCapture.color == painter.currentColor.toQVector());
					assert(shaderCapture.projection.isIdentity());
					painter.drawLegacyWideLines(array, count, offset, projection, mode);
					const auto& legacy = bufferCapture.vertices;
					if (mode != StelPainter::Lines)
					{
						assert(actual.size() == legacy.size());
						for (std::size_t vertex = 0; vertex < actual.size(); ++vertex) assert(equal(actual[vertex], legacy[vertex]));
					}
					else
						for (int segment = 0; segment < segments; ++segment)
							for (int corner = 0; corner < 6; ++corner)
								assert(equal(actual[segment * 6 + corner], legacy[segment * 12 + corner]));
					for (const auto& vertex : actual)
						for (int component = 0; component < 4; ++component) assert(std::isfinite(vertex[component]));
				}
}

static void testEndpointsWidthDepthAndColor()
{
	StelPainter painter;
	painter.glState.lineWidth = 4.f;
	const std::vector<Vec4f> input{{9, 9, 9, 1}, {-0.5f, 0.f, 0.2f, 1.f}, {0.5f, 0.f, 0.6f, 1.f},
		{0.f, -0.5f, -0.2f, 1.f}, {0.f, 0.5f, 0.8f, 1.f}, {9, 9, 9, 1}};
	const StelPainter::ArrayDesc array{GL_FLOAT, 4, input.data()};
	for (const float alpha : {0.f, 0.25f, 1.f})
	{
		painter.currentColor[3] = alpha;
		painter.drawFixedColorWideLinesAsQuads(array, 5, 1, Mat4f::identity(), StelPainter::Lines);
		const auto& vertices = bufferCapture.vertices;
		assert(vertices.size() == 12);
		for (int segment = 0; segment < 2; ++segment)
		{
			const auto& start = input[1 + segment * 2];
			const auto& end = input[2 + segment * 2];
			const auto* quad = vertices.data() + segment * 6;
			for (int axis = 0; axis < 2; ++axis)
			{
				assert(near((quad[0][axis] + quad[1][axis]) * 0.5f, start[axis]));
				assert(near((quad[2][axis] + quad[5][axis]) * 0.5f, end[axis]));
			}
			const float widthX = (quad[0][0] - quad[1][0]) * 500.f;
			const float widthY = (quad[0][1] - quad[1][1]) * 350.f;
			assert(near(std::hypot(widthX, widthY), 4.f));
			for (const int vertex : {0, 1, 4}) assert(quad[vertex][2] == start[2] && quad[vertex][3] == start[3]);
			for (const int vertex : {2, 3, 5}) assert(quad[vertex][2] == end[2] && quad[vertex][3] == end[3]);
		}
		assert(shaderCapture.color == painter.currentColor.toQVector());
	}
}

static void testLoopClosure()
{
	StelPainter painter;
	const std::vector<Vec4f> input{{-0.5f, -0.5f, 0, 1}, {0.5f, -0.5f, 0, 1}, {0.5f, 0.5f, 0, 1}, {-0.5f, 0.5f, 0, 1}};
	painter.drawFixedColorWideLinesAsQuads({GL_FLOAT, 4, input.data()}, 4, 0, Mat4f::identity(), StelPainter::LineLoop);
	const auto& vertices = bufferCapture.vertices;
	assert(vertices.size() == 24);
	assert(equal(vertices[18], vertices[15]) && equal(vertices[19], vertices[17]));
	assert(equal(vertices[20], vertices[0]) && equal(vertices[21], vertices[0]));
	assert(equal(vertices[22], vertices[17]) && equal(vertices[23], vertices[1]));
}

int main()
{
	testModesAgainstLegacy();
	testEndpointsWidthDepthAndColor();
	testLoopClosure();
	std::cout << "Wide lines: 144 mode/count/format/offset cases plus endpoint/width/depth/color and loop closure passed\n";
}
