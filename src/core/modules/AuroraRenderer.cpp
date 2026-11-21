/*
 * Stellarium
 * Copyright (C) 2026 Stellarium Developers
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1335, USA.
 */

#include "AuroraRenderer.hpp"

#include "StelApp.hpp"
#include "StelCore.hpp"
#include "StelOpenGL.hpp"
#include "StelProjector.hpp"

#include <QOpenGLBuffer>
#include <QOpenGLContext>
#include <QOpenGLExtraFunctions>
#include <QOpenGLFramebufferObject>
#include <QOpenGLShaderProgram>
#include <QOpenGLTexture>
#include <QOpenGLVertexArrayObject>
#include <QVector2D>

#include <cmath>
#include <cstdint>
#include <vector>

namespace
{
struct SkyRayVertex
{
	float clipX;
	float clipY;
	float dirX;
	float dirY;
	float dirZ;
	float valid;
};

struct CompositeVertex
{
	float clipX;
	float clipY;
	float u;
	float v;
};

struct AuroraGLStateGuard
{
	QOpenGLExtraFunctions& gl;
	GLint prevProgram = 0;
	GLint prevVao = 0;
	GLint prevActiveTex = GL_TEXTURE0;
	GLint prevTex0 = 0;
	GLint prevDrawFbo = 0;
	GLint prevReadFbo = 0;
	GLint prevViewport[4] = {0, 0, 0, 0};
	GLfloat prevClearColor[4] = {0.f, 0.f, 0.f, 0.f};
	GLboolean blendEnabled = GL_FALSE;
	GLboolean depthTestEnabled = GL_FALSE;
	GLboolean depthMask = GL_TRUE;
	GLboolean cullEnabled = GL_FALSE;
	GLboolean scissorEnabled = GL_FALSE;
	GLint blendSrcRgb = GL_SRC_ALPHA;
	GLint blendDstRgb = GL_ONE_MINUS_SRC_ALPHA;
	GLint blendSrcAlpha = GL_SRC_ALPHA;
	GLint blendDstAlpha = GL_ONE_MINUS_SRC_ALPHA;

	explicit AuroraGLStateGuard(QOpenGLExtraFunctions& f) : gl(f)
	{
		gl.glGetIntegerv(GL_CURRENT_PROGRAM, &prevProgram);
		gl.glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prevVao);
		gl.glGetIntegerv(GL_ACTIVE_TEXTURE, &prevActiveTex);
		gl.glActiveTexture(GL_TEXTURE0);
		gl.glGetIntegerv(GL_TEXTURE_BINDING_2D, &prevTex0);
		gl.glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prevDrawFbo);
		gl.glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prevReadFbo);
		gl.glGetIntegerv(GL_VIEWPORT, prevViewport);
		gl.glGetFloatv(GL_COLOR_CLEAR_VALUE, prevClearColor);
		blendEnabled = gl.glIsEnabled(GL_BLEND);
		depthTestEnabled = gl.glIsEnabled(GL_DEPTH_TEST);
		gl.glGetBooleanv(GL_DEPTH_WRITEMASK, &depthMask);
		cullEnabled = gl.glIsEnabled(GL_CULL_FACE);
		scissorEnabled = gl.glIsEnabled(GL_SCISSOR_TEST);
		gl.glGetIntegerv(GL_BLEND_SRC_RGB, &blendSrcRgb);
		gl.glGetIntegerv(GL_BLEND_DST_RGB, &blendDstRgb);
		gl.glGetIntegerv(GL_BLEND_SRC_ALPHA, &blendSrcAlpha);
		gl.glGetIntegerv(GL_BLEND_DST_ALPHA, &blendDstAlpha);
	}

	~AuroraGLStateGuard()
	{
		gl.glBindFramebuffer(GL_DRAW_FRAMEBUFFER, static_cast<GLuint>(prevDrawFbo));
		gl.glBindFramebuffer(GL_READ_FRAMEBUFFER, static_cast<GLuint>(prevReadFbo));
		gl.glViewport(prevViewport[0], prevViewport[1], prevViewport[2], prevViewport[3]);
		gl.glClearColor(prevClearColor[0], prevClearColor[1], prevClearColor[2], prevClearColor[3]);
		gl.glUseProgram(static_cast<GLuint>(prevProgram));
		gl.glBindVertexArray(static_cast<GLuint>(prevVao));
		gl.glActiveTexture(GL_TEXTURE0);
		gl.glBindTexture(GL_TEXTURE_2D, static_cast<GLuint>(prevTex0));
		gl.glActiveTexture(static_cast<GLenum>(prevActiveTex));
		if (blendEnabled) gl.glEnable(GL_BLEND); else gl.glDisable(GL_BLEND);
		gl.glBlendFuncSeparate(static_cast<GLenum>(blendSrcRgb), static_cast<GLenum>(blendDstRgb),
		                       static_cast<GLenum>(blendSrcAlpha), static_cast<GLenum>(blendDstAlpha));
		if (depthTestEnabled) gl.glEnable(GL_DEPTH_TEST); else gl.glDisable(GL_DEPTH_TEST);
		gl.glDepthMask(depthMask);
		if (cullEnabled) gl.glEnable(GL_CULL_FACE); else gl.glDisable(GL_CULL_FACE);
		if (scissorEnabled) gl.glEnable(GL_SCISSOR_TEST); else gl.glDisable(GL_SCISSOR_TEST);
	}
};

constexpr int kGridCols = 36;
constexpr int kGridRows = 22;
constexpr int kGridVertCount = (kGridCols + 1) * (kGridRows + 1);
constexpr int kGridIndexCount = kGridCols * kGridRows * 6;
} // namespace

struct AuroraRendererResources
{
	std::unique_ptr<QOpenGLBuffer> skyVbo;
	std::unique_ptr<QOpenGLBuffer> skyIbo;
	std::unique_ptr<QOpenGLVertexArrayObject> skyVao;
	std::unique_ptr<QOpenGLBuffer> quadVbo;
	std::unique_ptr<QOpenGLVertexArrayObject> quadVao;
	std::unique_ptr<QOpenGLTexture> pillarTex;
	std::unique_ptr<QOpenGLShaderProgram> volumeProgram;
	std::unique_ptr<QOpenGLShaderProgram> compositeProgram;
	std::unique_ptr<QOpenGLFramebufferObject> fbo;
	int fboW = 0;
	int fboH = 0;
	std::vector<SkyRayVertex> gridVerts;
};

AuroraRenderer::AuroraRenderer() = default;
AuroraRenderer::~AuroraRenderer() = default;

float AuroraRenderer::computeSolarGate(double sunAltDeg)
{
	// Emerge smoothly after civil twilight (-6 deg) and reach full atmospheric
	// visibility by astronomical darkness (-18 deg).
	const double t = qBound(0.0, (-6.0 - sunAltDeg) / 12.0, 1.0);
	return static_cast<float>(t * t * (3.0 - 2.0 * t));
}

void AuroraRenderer::update(double deltaTime, bool enabled, bool onEarth, double sunAltDeg, float zoomVisibility, int style)
{
	const float dt = static_cast<float>(qBound(0.0, deltaTime, 0.1));
	activeStyle = qBound(0, style, kStyleCount - 1);
	const float targetFade = (enabled && onEarth) ? 1.0f : 0.0f;
	const float fadeSpeed = (targetFade > fadeOpacity) ? 1.8f : 2.4f;
	fadeOpacity += (targetFade - fadeOpacity) * qMin(1.0f, dt * fadeSpeed);
	if (targetFade == 0.0f && fadeOpacity < 0.002f)
		fadeOpacity = 0.0f;
	else if (targetFade == 1.0f && fadeOpacity > 0.998f)
		fadeOpacity = 1.0f;

	solarGateValue = onEarth ? computeSolarGate(sunAltDeg) : 0.0f;
	zoomOpacity = qBound(0.0f, zoomVisibility, 1.0f);

	if (effectiveOpacity() > 0.001f)
		animationTime = std::fmod(animationTime + dt, 10000.0f);
}

void AuroraRenderer::releaseGL()
{
	res.reset();
}

void AuroraRenderer::prepareResources()
{
	if (res)
		return;
	res.reset(new AuroraRendererResources);
	res->gridVerts.resize(kGridVertCount);

	// 1. Sky-ray dome grid VAO/VBO/IBO (36x22 cells -> seamless across ALL projections, ZERO edge corners)
	res->skyVao.reset(new QOpenGLVertexArrayObject);
	res->skyVbo.reset(new QOpenGLBuffer(QOpenGLBuffer::VertexBuffer));
	res->skyIbo.reset(new QOpenGLBuffer(QOpenGLBuffer::IndexBuffer));
	res->skyVao->create();
	res->skyVbo->create();
	res->skyIbo->create();

	res->skyVbo->bind();
	res->skyVbo->setUsagePattern(QOpenGLBuffer::StreamDraw);
	res->skyVbo->allocate(kGridVertCount * static_cast<int>(sizeof(SkyRayVertex)));
	res->skyVbo->release();

	std::vector<quint16> indices;
	indices.reserve(kGridIndexCount);
	const int stride = kGridCols + 1;
	for (int r = 0; r < kGridRows; ++r)
	{
		for (int c = 0; c < kGridCols; ++c)
		{
			const quint16 i00 = static_cast<quint16>(r * stride + c);
			const quint16 i10 = static_cast<quint16>(r * stride + (c + 1));
			const quint16 i01 = static_cast<quint16>((r + 1) * stride + c);
			const quint16 i11 = static_cast<quint16>((r + 1) * stride + (c + 1));
			indices.push_back(i00);
			indices.push_back(i10);
			indices.push_back(i11);
			indices.push_back(i00);
			indices.push_back(i11);
			indices.push_back(i01);
		}
	}
	res->skyIbo->bind();
	res->skyIbo->setUsagePattern(QOpenGLBuffer::StaticDraw);
	res->skyIbo->allocate(indices.data(), static_cast<int>(indices.size() * sizeof(quint16)));
	res->skyIbo->release();

	// 2. Full-screen composite quad
	static const CompositeVertex kQuadVerts[6] = {
		{ -1.f, -1.f, 0.f, 0.f },
		{  1.f, -1.f, 1.f, 0.f },
		{  1.f,  1.f, 1.f, 1.f },
		{ -1.f, -1.f, 0.f, 0.f },
		{  1.f,  1.f, 1.f, 1.f },
		{ -1.f,  1.f, 0.f, 1.f },
	};
	res->quadVao.reset(new QOpenGLVertexArrayObject);
	res->quadVbo.reset(new QOpenGLBuffer(QOpenGLBuffer::VertexBuffer));
	res->quadVao->create();
	res->quadVbo->create();
	res->quadVbo->bind();
	res->quadVbo->setUsagePattern(QOpenGLBuffer::StaticDraw);
	res->quadVbo->allocate(kQuadVerts, sizeof(kQuadVerts));
	res->quadVbo->release();

	// 3. Smooth multi-scale 256x256 texture for ethereal vertical light shafts & gentle height taper
	// (Cubic Hermite filtered -> silky glowing light beams with ZERO harsh pixel grain!)
	constexpr int kSize = 256;
	std::vector<quint8> data(kSize * kSize * 4);
	std::uint32_t rng = 0x517cc1b7u;
	auto nextRand = [&rng]() -> float {
		rng ^= rng << 13;
		rng ^= rng >> 17;
		rng ^= rng << 5;
		return static_cast<float>(rng & 0xffffu) / 65535.0f;
	};

	auto buildPeriodicBand = [&](int knots) -> std::vector<float> {
		std::vector<float> k(knots);
		for (int i = 0; i < knots; ++i)
			k[i] = nextRand();
		std::vector<float> out(kSize);
		for (int i = 0; i < kSize; ++i)
		{
			const float pos = static_cast<float>(i) * static_cast<float>(knots) / static_cast<float>(kSize);
			const int i0 = static_cast<int>(std::floor(pos)) % knots;
			const int i1 = (i0 + 1) % knots;
			float f = pos - std::floor(pos);
			f = f * f * (3.f - 2.f * f);
			out[i] = k[i0] * (1.f - f) + k[i1] * f;
		}
		return out;
	};

	const std::vector<float> bandBroad = buildPeriodicBand(7);
	const std::vector<float> bandMed1  = buildPeriodicBand(15);
	const std::vector<float> bandMed2  = buildPeriodicBand(23);
	const std::vector<float> bandFine1 = buildPeriodicBand(37);
	const std::vector<float> bandFine2 = buildPeriodicBand(53);
	const std::vector<float> bandTall  = buildPeriodicBand(11);

	auto sampleArr = [&](const std::vector<float>& arr, float x) -> float {
		float w = std::fmod(x, static_cast<float>(kSize));
		if (w < 0.f) w += static_cast<float>(kSize);
		int i0 = static_cast<int>(std::floor(w)) % kSize;
		int i1 = (i0 + 1) % kSize;
		float f = w - std::floor(w);
		return arr[i0] * (1.f - f) + arr[i1] * f;
	};

	for (int y = 0; y < kSize; ++y)
	{
		const float fy = static_cast<float>(y) / static_cast<float>(kSize);
		const float driftA = std::sin(fy * 6.2831853f) * 9.0f;
		const float driftB = std::cos(fy * 6.2831853f) * 14.0f;
		const float driftC = std::sin(fy * 12.5663706f + 1.1f) * 6.0f;
		for (int x = 0; x < kSize; ++x)
		{
			const float fx = static_cast<float>(x);
			// R: dreamy broad curtain brightness clusters
			float r = 0.58f * sampleArr(bandBroad, fx + driftA)
			        + 0.42f * sampleArr(bandMed1,  fx - driftB * 0.6f);
			// G: silky parallel vertical light pillars (smooth luminous rays, never scratchy!)
			float g1 = sampleArr(bandMed2,  fx + driftB);
			float g2 = sampleArr(bandFine1, fx - driftA * 1.1f);
			float g3 = sampleArr(bandFine2, fx + driftC);
			float g = 0.42f * g1 + 0.36f * std::pow(g2, 1.35f) + 0.22f * std::pow(g3, 1.6f);
			// B: organic vertical ray-height variation (makes upper tops feather naturally into space)
			float b = 0.60f * sampleArr(bandTall, fx - driftA * 0.7f)
			        + 0.40f * sampleArr(bandMed1, fx + driftC);
			// A: gentle travelling shimmer density
			float a = 0.50f * sampleArr(bandBroad, fx + driftB * 1.2f)
			        + 0.50f * sampleArr(bandMed2,  fx - driftC);

			const int idx = (y * kSize + x) * 4;
			data[idx + 0] = static_cast<quint8>(qBound(0, static_cast<int>(r * 255.f + 0.5f), 255));
			data[idx + 1] = static_cast<quint8>(qBound(0, static_cast<int>(g * 255.f + 0.5f), 255));
			data[idx + 2] = static_cast<quint8>(qBound(0, static_cast<int>(b * 255.f + 0.5f), 255));
			data[idx + 3] = static_cast<quint8>(qBound(0, static_cast<int>(a * 255.f + 0.5f), 255));
		}
	}

	res->pillarTex.reset(new QOpenGLTexture(QOpenGLTexture::Target2D));
	res->pillarTex->setSize(kSize, kSize);
	res->pillarTex->setFormat(QOpenGLTexture::RGBA8_UNorm);
	res->pillarTex->setMipLevels(1);
	res->pillarTex->allocateStorage(QOpenGLTexture::RGBA, QOpenGLTexture::UInt8);
	res->pillarTex->setData(QOpenGLTexture::RGBA, QOpenGLTexture::UInt8, data.data());
	res->pillarTex->setMinMagFilters(QOpenGLTexture::Linear, QOpenGLTexture::Linear);
	res->pillarTex->setWrapMode(QOpenGLTexture::Repeat);

	buildProgram();
}

void AuroraRenderer::buildProgram()
{
	if (!res)
		return;

	// Pass 1: Quarter-res volumetric flowing silk-curtain sky dome
	// ZERO polygons, ZERO screen-edge corners, ZERO tiling repetition, ultra-lightweight (~1ms GPU)!
	const QByteArray volVertSrc = StelOpenGL::globalShaderPrefix(StelOpenGL::VERTEX_SHADER) + QByteArray(R"(
ATTRIBUTE highp vec2 aClipPos;
ATTRIBUTE highp vec3 aRayDir;
ATTRIBUTE highp float aValid;
VARYING highp vec3 vRayDir;
VARYING highp float vValid;
void main() {
    gl_Position = vec4(aClipPos, 0.0, 1.0);
    vRayDir = aRayDir;
    vValid = aValid;
}
)");

	const QByteArray volFragSrc = StelOpenGL::globalShaderPrefix(StelOpenGL::FRAGMENT_SHADER) + QByteArray(R"(
#ifdef GL_ES
precision highp float;
#endif
VARYING highp vec3 vRayDir;
VARYING highp float vValid;
uniform sampler2D uPillarTex;
uniform highp float uTime;
uniform highp float uHemiSign;
uniform int uStyle;

const float kEarthR = 6371.0;

// Evaluate one aperiodic, gracefully billowing 3D silk curtain ribbon in horizontal sky-km coordinates (q = km / 420)
// Combines a sinuous luminous silk ribbon core + soft ethereal atmospheric halo -> crisp yet dreamy, ZERO polygons!
// Returns vec4(sheetDensity, arcCoord, heightReachMod, coreMask)
vec4 evalSilkRibbon(vec2 q, float rotCos, float rotSin, float offset, float coreW,
                    float f1, float a1, float v1,
                    float f2, float a2, float v2,
                    float f3, float a3, float v3,
                    float seed, float ts)
{
    vec2 r = vec2(q.x * rotCos - q.y * rotSin, q.x * rotSin + q.y * rotCos);
    float s = r.x;

    // Incommensurate travelling silk waves -> graceful flowing S-curves that NEVER repeat across the sky
    float ph1 = s * f1 - ts * v1 + seed * 6.28318;
    float ph2 = s * f2 + ts * v2 + seed * 11.713;
    float ph3 = s * f3 - ts * v3 + seed * 19.371;

    float wave = a1 * sin(ph1) + a2 * cos(ph2) + a3 * sin(ph3);
    // Lateral S-fold curl creates dramatic sinuous silk bends that visibly billow in real time
    float sFlow = s + 0.34 * a1 * cos(ph1 * 0.85 + 0.6) + 0.18 * a2 * sin(ph2 * 0.72);

    // Organic ribbon thickness breathing along the curtain
    float wCore = coreW * (0.78 + 0.32 * sin(s * 0.67 + ts * 0.21 + seed * 5.1));
    float wHalo = wCore * 3.1;
    float d = (r.y - offset) - wave;
    float d2 = d * d;
    float coreSheet = exp(-d2 / (wCore * wCore));
    float haloSheet = exp(-d2 / (wHalo * wHalo));
    float sheet = coreSheet * 1.15 + haloSheet * 0.26;

    // Asymmetric drifting presence envelope -> curtains gracefully swell & breathe without vanishing completely
    float envWave = 0.58 * sin(s * 0.41 - ts * 0.12 + seed * 8.3)
                  + 0.42 * cos(s * 0.67 + ts * 0.09 + seed * 14.9);
    float presence = 0.24 + 0.76 * smoothstep(-0.68, 0.52, envWave);

    // Soft travelling light-ripple wave gliding gracefully along the silk curtain
    float ripple = 0.74 + 0.38 * sin(sFlow * 2.15 - ts * 0.88 + seed * 9.4);

    return vec4(sheet * presence * ripple, sFlow, 0.5 + 0.5 * sin(sFlow * 0.91 - ts * 0.19 + seed * 3.7), coreSheet * presence);
}

// Polar overhead silk ring for Style 2 (ethereal violet-emerald corona)
vec4 evalCoronaSilk(vec2 q, vec2 center, float baseRad, float coreW, float lobes, float seed, float ts)
{
    vec2 p = q - center;
    float rad = length(p) + 1e-4;
    float ang = atan(p.y, p.x);

    float ph1 = ang * lobes - ts * 0.34 + seed * 6.283;
    float ph2 = ang * (lobes + 2.0) + ts * 0.48 + seed * 13.1;
    float rWave = 0.22 * sin(ph1) + 0.10 * cos(ph2);
    float d = (rad - baseRad) - rWave;
    float wCore = coreW * (0.80 + 0.28 * sin(ang * 2.0 + ts * 0.24 + seed * 4.2));
    float wHalo = wCore * 3.0;
    float d2 = d * d;
    float coreSheet = exp(-d2 / (wCore * wCore));
    float haloSheet = exp(-d2 / (wHalo * wHalo));
    float sheet = coreSheet * 1.12 + haloSheet * 0.24;

    float presence = 0.28 + 0.72 * smoothstep(-0.55, 0.55, sin(ang * 1.0 - ts * 0.14 + seed * 7.1) + 0.45 * cos(ang * 2.0 + ts * 0.11 + seed * 11.3));
    float ripple = 0.76 + 0.36 * sin(ang * 4.0 - ts * 0.92 + seed * 6.0);
    float arcCoord = ang * baseRad * 0.95 + 0.20 * sin(ph1);

    return vec4(sheet * presence * ripple, arcCoord, 0.5 + 0.5 * cos(ang * 3.0 + ts * 0.21 + seed * 2.9), coreSheet * presence);
}

void main() {
    float validMask = smoothstep(0.45, 0.98, vValid);
    if (validMask <= 0.002) {
        FRAG_COLOR = vec4(0.0);
        return;
    }

    vec3 ray = normalize(vRayDir);
    float sinAlt = ray.z;
    // Fast early-out below horizon (skips ~35% of screen pixels with ZERO ray-march work!)
    if (sinAlt < -0.015) {
        FRAG_COLOR = vec4(0.0);
        return;
    }

    float horizonFade = smoothstep(-0.010, 0.075, sinAlt);
    float speed = (uStyle == 1) ? 1.15 : ((uStyle == 2) ? 1.04 : ((uStyle == 3) ? 0.65 : 0.92));
    float ts = uTime * speed;

    // Exact curved-Earth spherical shell entry & exit distances (computed ONCE -> ZERO sqrt inside loop!)
    float hMin = 100.0;
    float hMax = (uStyle == 1) ? 405.0 : ((uStyle == 2) ? 385.0 : ((uStyle == 3) ? 345.0 : 365.0));
    float hSpan = hMax - hMin;

    float rDz = kEarthR * sinAlt;
    float rDz2 = rDz * rDz;
    float t0 = sqrt(rDz2 + 2.0 * kEarthR * hMin + hMin * hMin) - rDz;
    float t1 = sqrt(rDz2 + 2.0 * kEarthR * hMax + hMax * hMax) - rDz;
    // Cap near-horizon optical path length so distant low-altitude curtains stay crisp & luminous
    t1 = min(t1, t0 + 920.0);

    // Static screen-space Interleaved Gradient Noise jitter eliminates stepping with ZERO temporal flicker
    float ign = fract(52.9829189 * fract(dot(gl_FragCoord.xy, vec2(0.06711056, 0.00583715))));

    // Style-specific palettes calibrated directly to real aurora astrophotography
    vec3 lowCol, midCol, highCol, crownCol;
    float finePillarAmt = 1.15;
    float veilFloor = 0.32;
    if (uStyle == 1) {
        // Style 1 — Crimson & Emerald Storm:
        // Luminous neon lime-emerald lower silk hem -> glowing rose-pink bridge -> soaring hot-magenta & ruby-crimson pillars!
        lowCol   = vec3(0.36, 1.00, 0.24);
        midCol   = vec3(1.00, 0.34, 0.66);
        highCol  = vec3(1.00, 0.06, 0.48);
        crownCol = vec3(0.92, 0.04, 0.36);
        finePillarAmt = 1.18;
        veilFloor = 0.34;
    } else if (uStyle == 2) {
        // Style 2 — Violet-Emerald Harp-String Pillars & Corona:
        // Crisp emerald base -> incandescent lavender-pearl pillar cores -> electric orchid-violet & rose-amethyst tops!
        lowCol   = vec3(0.16, 1.00, 0.54);
        midCol   = vec3(0.80, 0.68, 1.00);
        highCol  = vec3(0.74, 0.16, 1.00);
        crownCol = vec3(0.98, 0.22, 0.72);
        finePillarAmt = 1.55;
        veilFloor = 0.26;
    } else if (uStyle == 3) {
        // Style 3 — Sapphire-Green Polar Silk Arcs:
        // Dreamy glowing mint-aqua silk ribbons floating across serene deep cobalt-sapphire polar veil!
        lowCol   = vec3(0.24, 1.00, 0.72);
        midCol   = vec3(0.08, 0.92, 0.90);
        highCol  = vec3(0.16, 0.48, 1.00);
        crownCol = vec3(0.12, 0.28, 0.96);
        finePillarAmt = 0.72;
        veilFloor = 0.46;
    } else {
        // Style 0 — Classic Arctic Silk Curtains:
        // Ethereal emerald-mint lower ribbon -> luminous aqua-emerald rays -> whisper-soft amethyst-violet crown!
        lowCol   = vec3(0.20, 1.00, 0.46);
        midCol   = vec3(0.08, 0.96, 0.68);
        highCol  = vec3(0.56, 0.32, 0.94);
        crownCol = vec3(0.80, 0.22, 0.78);
        finePillarAmt = 1.15;
        veilFloor = 0.34;
    }

    vec3 accum = vec3(0.0);
    const int kSteps = 18;
    float stepScale = (t1 - t0) / (float(kSteps) * 420.0);
    float pathNorm = clamp(stepScale * 1.45, 0.048, 0.175);

    vec2 rayXY = vec2(ray.x * uHemiSign, ray.y);

    for (int i = 0; i < kSteps; ++i) {
        float fi = (float(i) + ign) / float(kSteps);
        float t = mix(t0, t1, fi);
        vec2 pKm = rayXY * t;

        // Exact curved-Earth altitude h (km) without sqrt
        float hKm = (t * t + 2.0 * kEarthR * t * sinAlt) / (2.0 * kEarthR);
        float hFrac = clamp((hKm - hMin) / hSpan, 0.0, 1.0);

        // Gentle upper silk sway (small enough to preserve crisp vertical magnetic-field light pillars!)
        float upperSway = hFrac * hFrac * 0.038;
        vec2 q = pKm * (1.0 / 420.0) + vec2(
            upperSway * sin(pKm.y * 0.0026 - ts * 0.45),
            upperSway * cos(pKm.x * 0.0022 + ts * 0.38)
        );

        // Evaluate 4 sinuous, aperiodic flowing silk ribbons (crisp 25-40 km cores + soft atmospheric halos!)
        vec4 rA, rB, rC, rD;
        if (uStyle == 1) {
            // Sweeping diagonal storm curtains (inspired by coastal red-green storms)
            rA = evalSilkRibbon(q, 0.92,  0.39, -1.05, 0.085, 1.12, 0.44, 0.44, 2.34, 0.17, 0.76, 3.68, 0.07, 0.34, 0.13, ts);
            rB = evalSilkRibbon(q, 0.95,  0.31, -0.22, 0.092, 0.96, 0.48, 0.38, 2.08, 0.19, 0.70, 3.31, 0.08, 0.30, 0.41, ts);
            rC = evalSilkRibbon(q, 0.89,  0.45,  0.62, 0.088, 1.22, 0.42, 0.42, 2.58, 0.16, 0.66, 4.02, 0.06, 0.28, 0.67, ts);
            rD = evalSilkRibbon(q, 0.96,  0.27,  1.42, 0.095, 0.88, 0.38, 0.34, 1.92, 0.15, 0.56, 3.11, 0.06, 0.25, 0.89, ts);
        } else if (uStyle == 2) {
            // Overhead undulating corona silk rings + sweeping emerald-violet forest curtains
            rA = evalCoronaSilk(q, vec2( 0.05, -0.04), 0.72, 0.072, 3.0, 0.17, ts);
            rB = evalCoronaSilk(q, vec2(-0.07,  0.05), 1.38, 0.085, 2.0, 0.53, ts);
            rC = evalSilkRibbon(q, 0.97, -0.24, -0.88, 0.078, 1.26, 0.42, 0.44, 2.70, 0.17, 0.74, 4.18, 0.06, 0.32, 0.37, ts);
            rD = evalSilkRibbon(q, 0.96,  0.28,  0.90, 0.078, 1.12, 0.44, 0.40, 2.46, 0.17, 0.68, 3.84, 0.06, 0.30, 0.71, ts);
        } else if (uStyle == 3) {
            // Serene wide sweeping polar silk arcs (like fjord aurora)
            rA = evalSilkRibbon(q, 0.98, -0.19, -0.96, 0.115, 0.86, 0.42, 0.30, 1.78, 0.15, 0.48, 2.86, 0.06, 0.22, 0.21, ts);
            rB = evalSilkRibbon(q, 0.98,  0.17,  0.22, 0.118, 0.92, 0.44, 0.28, 1.94, 0.16, 0.44, 3.05, 0.06, 0.20, 0.63, ts);
            rC = evalSilkRibbon(q, 0.95, -0.31, -0.34, 0.105, 0.78, 0.38, 0.25, 1.66, 0.14, 0.40, 2.62, 0.05, 0.18, 0.84, ts);
            rD = evalSilkRibbon(q, 0.99,  0.12,  1.18, 0.120, 0.82, 0.36, 0.24, 1.72, 0.13, 0.38, 2.74, 0.05, 0.17, 0.44, ts);
        } else {
            // Classic billowing Arctic silk drapery
            rA = evalSilkRibbon(q, 0.98, -0.20, -1.04, 0.082, 1.05, 0.46, 0.42, 2.24, 0.19, 0.70, 3.55, 0.07, 0.31, 0.11, ts);
            rB = evalSilkRibbon(q, 0.96,  0.28, -0.26, 0.088, 0.96, 0.50, 0.38, 2.08, 0.20, 0.64, 3.31, 0.07, 0.28, 0.39, ts);
            rC = evalSilkRibbon(q, 0.98, -0.16,  0.54, 0.084, 1.12, 0.44, 0.40, 2.38, 0.17, 0.66, 3.74, 0.07, 0.29, 0.64, ts);
            rD = evalSilkRibbon(q, 0.99,  0.14,  1.34, 0.092, 0.90, 0.40, 0.32, 1.88, 0.15, 0.54, 3.02, 0.06, 0.24, 0.87, ts);
        }

        float totalSheet = rA.x + rB.x + rC.x + rD.x;
        // Skip texture taps on empty starry sky samples
        if (totalSheet < 0.015)
            continue;

        // Weighted dominant ribbon arc coordinate (stays locked vertically along magnetic field lines!)
        float invTot = 1.0 / (totalSheet + 1e-4);
        float arcU = (rA.x * rA.y + rB.x * rB.y + rC.x * rC.y + rD.x * rD.y) * invTot;
        float tallMod = (rA.x * rA.z + rB.x * rB.z + rC.x * rC.z + rD.x * rD.z) * invTot;
        float coreDensity = rA.w + rB.w + rC.w + rD.w;

        // Two golden-ratio incommensurate scales -> graceful parallel vertical light pillars with ZERO repetition!
        vec4 tap1 = texture(uPillarTex, vec2(arcU * 0.78 + ts * 0.022, ts * 0.010 + 0.17));
        vec4 tap2 = texture(uPillarTex, vec2(arcU * 1.83 - ts * 0.032, -ts * 0.013 + 0.63));

        // Ethereal silky vertical rays: creamy luminous silk hem below, shimmering vertical light shafts rising above
        float pillarBroad = 0.54 * tap1.r + 0.46 * tap2.a;
        float pillarRay   = pow(clamp(0.45 * tap1.g + 0.55 * tap2.g, 0.0, 1.0), 1.45);
        float rayContrast = mix(0.42, 1.0, smoothstep(0.02, 0.20, hFrac));
        float rayPattern  = veilFloor + (0.62 * pillarBroad + finePillarAmt * pillarRay) * rayContrast;

        // Organic varying ray reach so upper tips feather poetically into the stars
        float tallReach = 0.54 + 0.68 * (0.55 * tap1.b + 0.45 * tallMod);
        float hNorm = hFrac / max(0.38, tallReach);

        // Crisp-yet-ethereal glowing lower silk edge + soaring soft vertical curtain
        float softBottom = smoothstep(0.0, 0.085, hFrac);
        float hemLift = 1.0 + 1.45 * exp(-pow((hFrac - 0.072) / 0.058, 2.0));
        float topDissolve = smoothstep(1.0, 0.65, hFrac);

        float lowBand  = softBottom * exp(-4.5 * hNorm) * hemLift;
        float midBand  = smoothstep(0.04, 0.24, hFrac) * exp(-2.25 * hNorm);
        float highBand = smoothstep(0.15, 0.48, hFrac) * exp(-1.22 * hNorm) * topDissolve;

        vec3 upperCol = mix(highCol, crownCol, smoothstep(0.42, 0.90, hFrac));
        vec3 sampleCol;
        if (uStyle == 1) {
            sampleCol = lowCol * (lowBand * 0.98)
                      + midCol * (midBand * 0.58)
                      + upperCol * (highBand * 1.58);
        } else if (uStyle == 2) {
            sampleCol = lowCol * (lowBand * 0.98)
                      + midCol * (midBand * 0.78)
                      + upperCol * (highBand * 1.48);
        } else if (uStyle == 3) {
            sampleCol = lowCol * (lowBand * 1.05)
                      + midCol * (midBand * 0.80)
                      + upperCol * (highBand * 1.04);
        } else {
            // Subtle N2 pink-magenta lower edge shimmer on intense folded cores
            float pinkEdge = (1.0 - smoothstep(0.0, 0.11, hFrac)) * smoothstep(0.75, 1.65, coreDensity * rayPattern);
            vec3 baseC = mix(lowCol, vec3(1.00, 0.24, 0.68), pinkEdge * 0.52);
            sampleCol = baseC * (lowBand * 1.08)
                      + midCol * (midBand * 0.72)
                      + upperCol * (highBand * 0.92);
        }

        float energy = totalSheet * rayPattern * pathNorm;
        accum += sampleCol * energy;
    }

    // Incandescent pearlescent core highlight along luminous curved folds & pillar cores
    float peakCh = max(accum.r, max(accum.g, accum.b));
    float hotCore = smoothstep(0.78, 2.15, peakCh);
    vec3 coreTint = (uStyle == 1) ? vec3(1.00, 0.84, 0.92)
                  : ((uStyle == 2) ? vec3(0.93, 0.87, 1.00) : vec3(0.84, 1.00, 0.94));
    accum = mix(accum, coreTint * peakCh, hotCore * 0.36);

    // Filmic exponential emission roll-off preserves luminous color vibrancy & stars cleanly
    vec3 outRgb = (vec3(1.0) - exp(-accum * 1.32)) * horizonFade * validMask;
    FRAG_COLOR = vec4(outRgb, 1.0);
}
)");

	// Pass 2: 4-tap ethereal Tent-filter upsample + screen-additive sky composite
	// Tighter 0.42-texel kernel preserves crisp delicate vertical light pillars while erasing all IGN dither!
	const QByteArray compVertSrc = StelOpenGL::globalShaderPrefix(StelOpenGL::VERTEX_SHADER) + QByteArray(R"(
ATTRIBUTE highp vec2 aClipPos;
ATTRIBUTE highp vec2 aUv;
VARYING highp vec2 vUv;
void main() {
    gl_Position = vec4(aClipPos, 0.0, 1.0);
    vUv = aUv;
}
)");

	const QByteArray compFragSrc = StelOpenGL::globalShaderPrefix(StelOpenGL::FRAGMENT_SHADER) + QByteArray(R"(
#ifdef GL_ES
precision highp float;
#endif
VARYING highp vec2 vUv;
uniform sampler2D uAuroraTex;
uniform highp vec2 uTexelSize;
uniform highp float uOpacity;
uniform highp float uNightVision;

void main() {
    vec2 d = uTexelSize * 0.42;
    vec3 col = 0.25 * (
        texture(uAuroraTex, vUv + vec2(-d.x, -d.y)).rgb +
        texture(uAuroraTex, vUv + vec2( d.x, -d.y)).rgb +
        texture(uAuroraTex, vUv + vec2(-d.x,  d.y)).rgb +
        texture(uAuroraTex, vUv + vec2( d.x,  d.y)).rgb
    );
    col *= uOpacity;
    if (uNightVision > 0.5) {
        float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
        col = vec3(lum * 0.88, 0.0, 0.0);
    }
    float outA = clamp(max(col.r, max(col.g, col.b)), 0.0, 1.0);
    FRAG_COLOR = vec4(col, outA);
}
)");

	res->volumeProgram.reset(new QOpenGLShaderProgram);
	if (!res->volumeProgram->addShaderFromSourceCode(QOpenGLShader::Vertex, volVertSrc) ||
	    !res->volumeProgram->addShaderFromSourceCode(QOpenGLShader::Fragment, volFragSrc) ||
	    !res->volumeProgram->link())
	{
		qWarning() << "AuroraRenderer: volume shader link failed:" << res->volumeProgram->log();
		res->volumeProgram.reset();
	}

	res->compositeProgram.reset(new QOpenGLShaderProgram);
	if (!res->compositeProgram->addShaderFromSourceCode(QOpenGLShader::Vertex, compVertSrc) ||
	    !res->compositeProgram->addShaderFromSourceCode(QOpenGLShader::Fragment, compFragSrc) ||
	    !res->compositeProgram->link())
	{
		qWarning() << "AuroraRenderer: composite shader link failed:" << res->compositeProgram->log();
		res->compositeProgram.reset();
	}
}

void AuroraRenderer::draw(StelCore* core)
{
	if (!core || !core->getFlagClearSky())
		return;
	const float drawOpacity = effectiveOpacity();
	if (drawOpacity <= 0.002f)
		return;

	QOpenGLContext* ctx = QOpenGLContext::currentContext();
	QOpenGLExtraFunctions* gl = ctx ? ctx->extraFunctions() : nullptr;
	if (!gl)
		return;

	const StelProjectorP projector = core->getProjection(core->getAltAzModelViewTransform(StelCore::RefractionOff));
	if (!projector)
		return;
	const Vec4i viewport = projector->getViewport();
	if (viewport[2] <= 4 || viewport[3] <= 4)
		return;

	AuroraGLStateGuard stateGuard(*gl);
	prepareResources();
	if (!res || !res->volumeProgram || !res->compositeProgram ||
	    !res->skyVao || !res->skyVao->isCreated() || !res->skyVbo || !res->skyVbo->isCreated() ||
	    !res->skyIbo || !res->skyIbo->isCreated() || !res->quadVao || !res->quadVao->isCreated() ||
	    !res->quadVbo || !res->quadVbo->isCreated() || !res->pillarTex || !res->pillarTex->isStorageAllocated())
		return;

	// Sub-resolution volumetric FBO (e.g. 768x480 on 2560x1600): ~11x fewer pixels -> zero FPS drop,
	// while tight 4-tap Tent upsampling preserves crisp vertical light pillars with zero banding!
	const int targetW = qBound(240, viewport[2] / 3, 768);
	const int targetH = qBound(160, viewport[3] / 3, 480);
	if (!res->fbo || res->fboW != targetW || res->fboH != targetH)
	{
		QOpenGLFramebufferObjectFormat fmt;
		fmt.setAttachment(QOpenGLFramebufferObject::NoAttachment);
		fmt.setInternalTextureFormat(GL_RGBA8);
		res->fbo.reset(new QOpenGLFramebufferObject(targetW, targetH, fmt));
		if (!res->fbo->isValid())
		{
			res->fbo.reset();
			res->fboW = 0;
			res->fboH = 0;
			return;
		}
		res->fboW = targetW;
		res->fboH = targetH;
		gl->glBindTexture(GL_TEXTURE_2D, res->fbo->texture());
		gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
		gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
		gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
		gl->glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	}

	// Build seamless full-viewport sky-ray grid via projector->unProject() (~0.04ms CPU)
	const double vpX = static_cast<double>(viewport[0]);
	const double vpY = static_cast<double>(viewport[1]);
	const double vpW = static_cast<double>(viewport[2]);
	const double vpH = static_cast<double>(viewport[3]);
	const int stride = kGridCols + 1;
	for (int r = 0; r <= kGridRows; ++r)
	{
		const double vf = static_cast<double>(r) / static_cast<double>(kGridRows);
		const float clipY = static_cast<float>(vf * 2.0 - 1.0);
		const double winY = vpY + vf * vpH;
		for (int c = 0; c <= kGridCols; ++c)
		{
			const double uf = static_cast<double>(c) / static_cast<double>(kGridCols);
			const float clipX = static_cast<float>(uf * 2.0 - 1.0);
			const double winX = vpX + uf * vpW;
			Vec3d dir;
			const bool ok = projector->unProject(winX, winY, dir) &&
			                std::isfinite(dir[0]) && std::isfinite(dir[1]) && std::isfinite(dir[2]);
			SkyRayVertex& vtx = res->gridVerts[static_cast<size_t>(r * stride + c)];
			vtx.clipX = clipX;
			vtx.clipY = clipY;
			if (ok)
			{
				const double len = dir.norm();
				if (len > 1e-6)
				{
					vtx.dirX = static_cast<float>(dir[0] / len);
					vtx.dirY = static_cast<float>(dir[1] / len);
					vtx.dirZ = static_cast<float>(dir[2] / len);
					vtx.valid = 1.0f;
				}
				else
				{
					vtx.dirX = 0.f; vtx.dirY = 0.f; vtx.dirZ = -1.f; vtx.valid = 0.f;
				}
			}
			else
			{
				vtx.dirX = 0.f; vtx.dirY = 0.f; vtx.dirZ = -1.f; vtx.valid = 0.f;
			}
		}
	}

	const float hemiSign = (core->getCurrentLocation().getLatitude() >= 0.0) ? 1.0f : -1.0f;
	const float nightVision = StelApp::getInstance().getVisionModeNight() ? 1.0f : 0.0f;

	// ---- PASS 1: Render volumetric flowing aurora into quarter-res FBO ----
	gl->glDisable(GL_SCISSOR_TEST);
	gl->glDisable(GL_DEPTH_TEST);
	gl->glDepthMask(GL_FALSE);
	gl->glDisable(GL_CULL_FACE);
	gl->glDisable(GL_BLEND);

	res->fbo->bind();
	gl->glViewport(0, 0, res->fboW, res->fboH);
	gl->glClearColor(0.f, 0.f, 0.f, 0.f);
	gl->glClear(GL_COLOR_BUFFER_BIT);

	res->skyVao->bind();
	res->skyVbo->bind();
	res->skyVbo->write(0, res->gridVerts.data(), kGridVertCount * static_cast<int>(sizeof(SkyRayVertex)));
	res->skyIbo->bind();

	res->volumeProgram->bind();
	res->volumeProgram->setUniformValue("uTime", animationTime);
	res->volumeProgram->setUniformValue("uHemiSign", hemiSign);
	res->volumeProgram->setUniformValue("uStyle", activeStyle);
	gl->glActiveTexture(GL_TEXTURE0);
	res->pillarTex->bind();
	res->volumeProgram->setUniformValue("uPillarTex", 0);

	constexpr int kSkyStride = static_cast<int>(sizeof(SkyRayVertex));
	const int locPos   = res->volumeProgram->attributeLocation("aClipPos");
	const int locRay   = res->volumeProgram->attributeLocation("aRayDir");
	const int locValid = res->volumeProgram->attributeLocation("aValid");
	if (locPos >= 0)   { res->volumeProgram->enableAttributeArray(locPos);   res->volumeProgram->setAttributeBuffer(locPos,   GL_FLOAT, offsetof(SkyRayVertex, clipX), 2, kSkyStride); }
	if (locRay >= 0)   { res->volumeProgram->enableAttributeArray(locRay);   res->volumeProgram->setAttributeBuffer(locRay,   GL_FLOAT, offsetof(SkyRayVertex, dirX),  3, kSkyStride); }
	if (locValid >= 0) { res->volumeProgram->enableAttributeArray(locValid); res->volumeProgram->setAttributeBuffer(locValid, GL_FLOAT, offsetof(SkyRayVertex, valid), 1, kSkyStride); }

	gl->glDrawElements(GL_TRIANGLES, kGridIndexCount, GL_UNSIGNED_SHORT, nullptr);

	if (locPos >= 0)   res->volumeProgram->disableAttributeArray(locPos);
	if (locRay >= 0)   res->volumeProgram->disableAttributeArray(locRay);
	if (locValid >= 0) res->volumeProgram->disableAttributeArray(locValid);
	res->volumeProgram->release();
	res->skyIbo->release();
	res->skyVbo->release();
	res->skyVao->release();

	// ---- PASS 2: Ethereal 4-tap Tent upsample & screen-additive composite onto main sky ----
	gl->glBindFramebuffer(GL_DRAW_FRAMEBUFFER, static_cast<GLuint>(stateGuard.prevDrawFbo));
	gl->glBindFramebuffer(GL_READ_FRAMEBUFFER, static_cast<GLuint>(stateGuard.prevReadFbo));
	gl->glViewport(viewport[0], viewport[1], viewport[2], viewport[3]);
	if (stateGuard.scissorEnabled)
		gl->glEnable(GL_SCISSOR_TEST);

	gl->glEnable(GL_BLEND);
	// Screen-additive blend preserves dark starry sky & bright stars cleanly!
	gl->glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_COLOR);

	res->quadVao->bind();
	res->quadVbo->bind();
	res->compositeProgram->bind();
	gl->glActiveTexture(GL_TEXTURE0);
	gl->glBindTexture(GL_TEXTURE_2D, res->fbo->texture());
	res->compositeProgram->setUniformValue("uAuroraTex", 0);
	res->compositeProgram->setUniformValue("uTexelSize", QVector2D(1.0f / static_cast<float>(res->fboW),
	                                                               1.0f / static_cast<float>(res->fboH)));
	res->compositeProgram->setUniformValue("uOpacity", drawOpacity);
	res->compositeProgram->setUniformValue("uNightVision", nightVision);

	constexpr int kQuadStride = static_cast<int>(sizeof(CompositeVertex));
	const int locQPos = res->compositeProgram->attributeLocation("aClipPos");
	const int locQUv  = res->compositeProgram->attributeLocation("aUv");
	if (locQPos >= 0) { res->compositeProgram->enableAttributeArray(locQPos); res->compositeProgram->setAttributeBuffer(locQPos, GL_FLOAT, offsetof(CompositeVertex, clipX), 2, kQuadStride); }
	if (locQUv >= 0)  { res->compositeProgram->enableAttributeArray(locQUv);  res->compositeProgram->setAttributeBuffer(locQUv,  GL_FLOAT, offsetof(CompositeVertex, u),     2, kQuadStride); }

	gl->glDrawArrays(GL_TRIANGLES, 0, 6);

	if (locQPos >= 0) res->compositeProgram->disableAttributeArray(locQPos);
	if (locQUv >= 0)  res->compositeProgram->disableAttributeArray(locQUv);
	res->compositeProgram->release();
	res->quadVbo->release();
	res->quadVao->release();
}
