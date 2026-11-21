#include "DetailModelNative.h"

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>
#include <string>
#include <vector>

namespace {

constexpr double kPi = 3.14159265358979323846;
constexpr double kTwoPi = 6.28318530717958647692;
constexpr float kInv255 = 1.0f / 255.0f;

inline int clampByte(double v) {
    if (v <= 0.0) return 0;
    if (v >= 255.0) return 255;
    return static_cast<int>(v + 0.5);
}

inline int clampByteF(float v) {
    if (v <= 0.0f) return 0;
    if (v >= 255.0f) return 255;
    return static_cast<int>(v + 0.5f);
}

bool readDoubleArg(napi_env env, napi_value val, double& out) {
    return napi_get_value_double(env, val, &out) == napi_ok && std::isfinite(out);
}

bool readIntArg(napi_env env, napi_value val, int32_t& out) {
    return napi_get_value_int32(env, val, &out) == napi_ok;
}

bool readBoolArg(napi_env env, napi_value val, bool& out) {
    return napi_get_value_bool(env, val, &out) == napi_ok;
}

bool readStringArg(napi_env env, napi_value val, std::string& out) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, val, nullptr, 0, &len) != napi_ok) return false;
    out.resize(len);
    if (len == 0) return true;
    size_t copied = 0;
    return napi_get_value_string_utf8(env, val, &out[0], len + 1, &copied) == napi_ok;
}

bool readTransform9(napi_env env, napi_value arrVal, double t[9]) {
    bool isTyped = false;
    if (napi_is_typedarray(env, arrVal, &isTyped) == napi_ok && isTyped) {
        napi_typedarray_type type;
        size_t len = 0;
        void* data = nullptr;
        napi_value ab = nullptr;
        size_t offset = 0;
        if (napi_get_typedarray_info(env, arrVal, &type, &len, &data, &ab, &offset) == napi_ok && len >= 9) {
            if (type == napi_float64_array) {
                const auto* p = static_cast<const double*>(data);
                for (int i = 0; i < 9; ++i) t[i] = p[i];
                return true;
            }
            if (type == napi_float32_array) {
                const auto* p = static_cast<const float*>(data);
                for (int i = 0; i < 9; ++i) t[i] = static_cast<double>(p[i]);
                return true;
            }
        }
    }
    uint32_t len = 0;
    if (napi_get_array_length(env, arrVal, &len) != napi_ok || len < 9) return false;
    for (uint32_t i = 0; i < 9; ++i) {
        napi_value elem = nullptr;
        if (napi_get_element(env, arrVal, i, &elem) != napi_ok) return false;
        if (!readDoubleArg(env, elem, t[i])) return false;
    }
    return true;
}

bool readOptionalArrayBuffer(napi_env env, napi_value val, const uint8_t*& data, size_t& len) {
    data = nullptr;
    len = 0;
    napi_valuetype vtype = napi_undefined;
    if (napi_typeof(env, val, &vtype) != napi_ok) return false;
    if (vtype == napi_undefined || vtype == napi_null) return true;
    bool isAb = false;
    if (napi_is_arraybuffer(env, val, &isAb) == napi_ok && isAb) {
        void* raw = nullptr;
        if (napi_get_arraybuffer_info(env, val, &raw, &len) == napi_ok) {
            data = static_cast<const uint8_t*>(raw);
            return true;
        }
    }
    return false;
}

napi_value createOutputArrayBuffer(napi_env env, int renderSize, uint8_t*& outPixels) {
    const size_t byteLen = static_cast<size_t>(renderSize) * static_cast<size_t>(renderSize) * 4;
    void* raw = nullptr;
    napi_value ab = nullptr;
    if (napi_create_arraybuffer(env, byteLen, &raw, &ab) != napi_ok || raw == nullptr) {
        outPixels = nullptr;
        return nullptr;
    }
    std::memset(raw, 0, byteLen);
    outPixels = static_cast<uint8_t*>(raw);
    return ab;
}

// ---------------------------------------------------------------------------
// 1. Textured Sphere + Optional Rings (Planets / Moon / Sun)
// ---------------------------------------------------------------------------
// Args (19):
// 0: texture (ArrayBuffer)
// 1: textureWidth (int)
// 2: textureHeight (int)
// 3: textureStride (int)
// 4: ringTexture (ArrayBuffer | undefined)
// 5: ringWidth (int)
// 6: ringHeight (int)
// 7: hasRing (bool)
// 8: ringInner (double)
// 9: ringOuter (double)
// 10: ringOpacity (double)
// 11: renderSize (int)
// 12: scale (double)
// 13: transform (number[9])
// 14: hasLighting (bool)
// 15: emissive (bool)
// 16: lightX (double)
// 17: lightY (double)
// 18: lightZ (double)
napi_value RenderDetailModelSphere(napi_env env, napi_callback_info info) {
    size_t argc = 19;
    napi_value args[19];
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 19) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    const uint8_t* texture = nullptr;
    size_t textureLen = 0;
    const uint8_t* ringTex = nullptr;
    size_t ringTexLen = 0;
    int32_t texW = 0, texH = 0, texStride = 0;
    int32_t ringW = 0, ringH = 0, renderSize = 0;
    bool hasRing = false, hasLighting = false, emissive = false;
    double ringInner = 0.0, ringOuter = 0.0, ringOpacity = 0.0, scale = 1.0;
    double lightX = 0.0, lightY = 0.0, lightZ = 1.0;
    double t[9];

    if (!readOptionalArrayBuffer(env, args[0], texture, textureLen) || texture == nullptr ||
        !readIntArg(env, args[1], texW) || !readIntArg(env, args[2], texH) || !readIntArg(env, args[3], texStride) ||
        !readOptionalArrayBuffer(env, args[4], ringTex, ringTexLen) ||
        !readIntArg(env, args[5], ringW) || !readIntArg(env, args[6], ringH) ||
        !readBoolArg(env, args[7], hasRing) ||
        !readDoubleArg(env, args[8], ringInner) || !readDoubleArg(env, args[9], ringOuter) || !readDoubleArg(env, args[10], ringOpacity) ||
        !readIntArg(env, args[11], renderSize) || !readDoubleArg(env, args[12], scale) ||
        !readTransform9(env, args[13], t) ||
        !readBoolArg(env, args[14], hasLighting) || !readBoolArg(env, args[15], emissive) ||
        !readDoubleArg(env, args[16], lightX) || !readDoubleArg(env, args[17], lightY) || !readDoubleArg(env, args[18], lightZ)) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    if (renderSize < 16 || renderSize > 1024 || texW <= 0 || texH <= 0 || texStride < texW * 4 ||
        static_cast<size_t>(texH - 1) * static_cast<size_t>(texStride) + static_cast<size_t>(texW) * 4 > textureLen) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    uint8_t* output = nullptr;
    napi_value resultAb = createOutputArrayBuffer(env, renderSize, output);
    if (!resultAb || !output) return nullptr;

    const double center = (renderSize - 1) * 0.5;
    const double ringScaleLimit = hasRing ? std::min(0.39, 0.46 / std::max(0.1, ringOuter)) : 0.39;
    const double radius = renderSize * ringScaleLimit * scale;
    const double invRadius = 1.0 / std::max(1e-6, radius);
    const double invTwoPi = 1.0 / kTwoPi;
    const double invPi = 1.0 / kPi;
    const double texHMinus1 = static_cast<double>(texH - 1);

    const float t0 = static_cast<float>(t[0]), t1 = static_cast<float>(t[1]), t2 = static_cast<float>(t[2]);
    const float t3 = static_cast<float>(t[3]), t4 = static_cast<float>(t[4]), t5 = static_cast<float>(t[5]);
    const float t6 = static_cast<float>(t[6]), t7 = static_cast<float>(t[7]), t8 = static_cast<float>(t[8]);
    const float lx = static_cast<float>(lightX), ly = static_cast<float>(lightY), lz = static_cast<float>(lightZ);
    const bool unlitOrSun = emissive || !hasLighting;

    const int firstRow = std::max(0, static_cast<int>(std::floor(center - radius)) - 1);
    const int lastRow = std::min(renderSize - 1, static_cast<int>(std::ceil(center + radius)) + 1);

    for (int y = firstRow; y <= lastRow; ++y) {
        const float sphereY = static_cast<float>((center - y) * invRadius);
        const float sy2 = sphereY * sphereY;
        if (sy2 > 1.0f) continue;
        const double extent = std::sqrt(static_cast<double>(1.0f - sy2)) * radius;
        const int firstCol = std::max(0, static_cast<int>(std::floor(center - extent)) - 1);
        const int lastCol = std::min(renderSize - 1, static_cast<int>(std::ceil(center + extent)) + 1);
        uint8_t* rowPtr = output + static_cast<size_t>(y) * static_cast<size_t>(renderSize) * 4;

        const float yT1 = t1 * sphereY;
        const float yT4 = t4 * sphereY;
        const float yT7 = t7 * sphereY;

        for (int x = firstCol; x <= lastCol; ++x) {
            const float sphereX = static_cast<float>((x - center) * invRadius);
            const float r2 = sphereX * sphereX + sy2;
            if (r2 > 1.0f) continue;

            const float sphereZ = std::sqrt(1.0f - r2);
            const float objX = t0 * sphereX + yT1 + t2 * sphereZ;
            const float objY = std::max(-1.0f, std::min(1.0f, t3 * sphereX + yT4 + t5 * sphereZ));
            const float objZ = t6 * sphereX + yT7 + t8 * sphereZ;

            double u = std::atan2(static_cast<double>(objX), static_cast<double>(objZ)) * invTwoPi + 0.5;
            u -= std::floor(u);
            double v = 0.5 - std::asin(static_cast<double>(objY)) * invPi;
            if (v < 0.0) v = 0.0;
            else if (v > 1.0) v = 1.0;

            const double tx = u * texW;
            const double ty = v * texHMinus1;
            const int x0 = static_cast<int>(tx) % texW;
            const int y0 = static_cast<int>(ty);
            const int x1 = (x0 + 1 == texW) ? 0 : (x0 + 1);
            const int y1 = (y0 + 1 < texH) ? (y0 + 1) : (texH - 1);
            const float fx = static_cast<float>(tx - std::floor(tx));
            const float fy = static_cast<float>(ty - y0);
            const float wx0 = 1.0f - fx;
            const float wy0 = 1.0f - fy;

            const uint8_t* p00 = texture + y0 * texStride + x0 * 4;
            const uint8_t* p10 = texture + y0 * texStride + x1 * 4;
            const uint8_t* p01 = texture + y1 * texStride + x0 * 4;
            const uint8_t* p11 = texture + y1 * texStride + x1 * 4;

            const float red = (p00[0] * wx0 + p10[0] * fx) * wy0 + (p01[0] * wx0 + p11[0] * fx) * fy;
            const float green = (p00[1] * wx0 + p10[1] * fx) * wy0 + (p01[1] * wx0 + p11[1] * fx) * fy;
            const float blue = (p00[2] * wx0 + p10[2] * fx) * wy0 + (p01[2] * wx0 + p11[2] * fx) * fy;

            float brightness = 1.0f;
            if (unlitOrSun) {
                brightness = 0.86f + sphereZ * 0.14f;
            } else {
                const float lightDot = objX * lx + objY * ly + objZ * lz;
                float tr = (lightDot + 0.08f) * 6.25f;
                if (tr < 0.0f) tr = 0.0f;
                else if (tr > 1.0f) tr = 1.0f;
                const float smoothLight = tr * tr * (3.0f - 2.0f * tr);
                brightness = (0.17f + 0.83f * smoothLight) * (0.80f + sphereZ * 0.20f);
            }

            uint8_t* dst = rowPtr + x * 4;
            dst[0] = static_cast<uint8_t>(clampByteF(red * brightness));
            dst[1] = static_cast<uint8_t>(clampByteF(green * brightness));
            dst[2] = static_cast<uint8_t>(clampByteF(blue * brightness));
            const float edgeAlpha = std::min(1.0f, std::max(0.0f, (1.0f - std::sqrt(r2)) * static_cast<float>(radius)));
            dst[3] = static_cast<uint8_t>(clampByteF(255.0f * edgeAlpha));
        }
    }

    // Fast Ring Pass with precomputed 1D LUT + tight bounding box.
    if (hasRing && ringTex != nullptr && ringW > 0 && ringH > 0 &&
        static_cast<size_t>(ringW) * static_cast<size_t>(ringH) * 4 <= ringTexLen &&
        std::abs(t[5]) >= 0.0001) {
        const int profileRadius = ringOuter > 3.0 ? 4 : 2;
        const float minRingAlpha = ringOuter > 3.0 ? 0.16f : 0.10f;
        const float opacityF = static_cast<float>(ringOpacity);

        // Precompute 1D radial LUT of size ringW (eliminates 18-tap inner loop per pixel).
        std::vector<uint8_t> ringLut(static_cast<size_t>(ringW) * 4, 0);
        for (int rx = 0; rx < ringW; ++rx) {
            const int startX = std::max(0, rx - profileRadius);
            const int endX = std::min(ringW - 1, rx + profileRadius);
            uint8_t bestA = 0, r = 0, g = 0, b = 0;
            for (int px = startX; px <= endX; ++px) {
                for (int py = 0; py < ringH; ++py) {
                    const uint8_t* p = ringTex + (py * ringW + px) * 4;
                    if (p[3] > bestA) {
                        bestA = p[3];
                        r = p[0];
                        g = p[1];
                        b = p[2];
                    }
                }
            }
            const float a = std::max((bestA * kInv255) * opacityF, minRingAlpha);
            ringLut[rx * 4 + 0] = r;
            ringLut[rx * 4 + 1] = g;
            ringLut[rx * 4 + 2] = b;
            ringLut[rx * 4 + 3] = static_cast<uint8_t>(clampByteF(a * 255.0f));
        }

        const double outerR = radius * ringOuter;
        const double innerR = radius * ringInner;
        const double outerR2 = outerR * outerR;
        const double innerR2 = innerR * innerR;
        const double spanInv = 1.0 / std::max(1.0, outerR - innerR);
        const double invT5 = -1.0 / t[5];
        const double rBound = std::min(static_cast<double>(renderSize), outerR + 2.0);
        const int rFirstRow = std::max(0, static_cast<int>(std::floor(center - rBound)));
        const int rLastRow = std::min(renderSize - 1, static_cast<int>(std::ceil(center + rBound)));
        const int rFirstCol = std::max(0, static_cast<int>(std::floor(center - rBound)));
        const int rLastCol = std::min(renderSize - 1, static_cast<int>(std::ceil(center + rBound)));

        for (int y = rFirstRow; y <= rLastRow; ++y) {
            const double normY = (center - y) * invRadius;
            const double normY2 = normY * normY;
            const double t4ny = t[4] * normY;
            uint8_t* rowPtr = output + static_cast<size_t>(y) * static_cast<size_t>(renderSize) * 4;

            for (int x = rFirstCol; x <= rLastCol; ++x) {
                const double normX = (x - center) * invRadius;
                const double screenZ = (t[3] * normX + t4ny) * invT5;
                // Because t is orthonormal, |object|^2 == normX^2 + normY^2 + screenZ^2!
                const double ringR2 = (normX * normX + normY2 + screenZ * screenZ) * radius * radius;
                if (ringR2 < innerR2 || ringR2 > outerR2) continue;

                const double sphereR2 = normX * normX + normY2;
                if (sphereR2 <= 1.0) {
                    const double planetFrontZ = std::sqrt(std::max(0.0, 1.0 - sphereR2));
                    if (screenZ <= planetFrontZ) continue;
                }

                const double ringR = std::sqrt(ringR2);
                const double radialPos = std::max(0.0, std::min(1.0, (ringR - innerR) * spanInv));
                const int lutIdx = std::min(ringW - 1, std::max(0, static_cast<int>(radialPos * (ringW - 1) + 0.5)));
                const uint8_t* lut = ringLut.data() + lutIdx * 4;
                const float srcA = lut[3] * kInv255;
                if (srcA <= 0.01f) continue;

                uint8_t* dst = rowPtr + x * 4;
                const float dstA = dst[3] * kInv255;
                const float invSrcA = 1.0f - srcA;
                const float combA = srcA + dstA * invSrcA;
                if (combA <= 0.0f) continue;
                const float invComb = 1.0f / combA;
                const float wDst = dstA * invSrcA;

                dst[0] = static_cast<uint8_t>(clampByteF((lut[0] * srcA + dst[0] * wDst) * invComb));
                dst[1] = static_cast<uint8_t>(clampByteF((lut[1] * srcA + dst[1] * wDst) * invComb));
                dst[2] = static_cast<uint8_t>(clampByteF((lut[2] * srcA + dst[2] * wDst) * invComb));
                dst[3] = static_cast<uint8_t>(clampByteF(combA * 255.0f));
            }
        }
    }

    return resultAb;
}

// ---------------------------------------------------------------------------
// 2. Procedural 3D Models (Star / Quasar / Pulsar / Clusters)
// ---------------------------------------------------------------------------
// Args (6):
// 0: kind (string)
// 1: temperature (double)
// 2: particlesFloat32 (Float32Array | ArrayBuffer, stride 8 floats: x,y,z,r,R,G,B,a)
// 3: renderSize (int)
// 4: scale (double)
// 5: transform (number[9])
napi_value RenderDetailModelProcedural(napi_env env, napi_callback_info info) {
    size_t argc = 6;
    napi_value args[6];
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 6) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    std::string kind;
    double temperature = 0.0, scale = 1.0;
    int32_t renderSize = 0;
    double t[9];
    if (!readStringArg(env, args[0], kind) ||
        !readDoubleArg(env, args[1], temperature) ||
        !readIntArg(env, args[3], renderSize) ||
        !readDoubleArg(env, args[4], scale) ||
        !readTransform9(env, args[5], t) ||
        renderSize < 16 || renderSize > 1024) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    const float* partPtr = nullptr;
    size_t partCount = 0;
    bool isTyped = false;
    if (napi_is_typedarray(env, args[2], &isTyped) == napi_ok && isTyped) {
        napi_typedarray_type type;
        size_t len = 0;
        void* data = nullptr;
        napi_value ab = nullptr;
        size_t offset = 0;
        if (napi_get_typedarray_info(env, args[2], &type, &len, &data, &ab, &offset) == napi_ok &&
            type == napi_float32_array && data != nullptr) {
            partPtr = static_cast<const float*>(data);
            partCount = len / 8;
        }
    }

    uint8_t* output = nullptr;
    napi_value resultAb = createOutputArrayBuffer(env, renderSize, output);
    if (!resultAb || !output) return nullptr;

    const float center = (renderSize - 1) * 0.5f;
    const float radius = static_cast<float>(renderSize * 0.39 * scale);
    const float invRadius = 1.0f / std::max(1e-5f, radius);

    float colR = 238.0f, colG = 242.0f, colB = 248.0f;
    if (std::isfinite(temperature) && temperature > 0.0) {
        if (temperature >= 11000.0) { colR = 168.0f; colG = 200.0f; colB = 255.0f; }
        else if (temperature >= 7500.0) { colR = 214.0f; colG = 229.0f; colB = 255.0f; }
        else if (temperature >= 6000.0) { colR = 255.0f; colG = 245.0f; colB = 216.0f; }
        else if (temperature >= 4500.0) { colR = 255.0f; colG = 211.0f; colB = 163.0f; }
        else { colR = 255.0f; colG = 170.0f; colB = 134.0f; }
    }

    const float t0 = static_cast<float>(t[0]), t1 = static_cast<float>(t[1]), t2 = static_cast<float>(t[2]);
    const float t3 = static_cast<float>(t[3]), t4 = static_cast<float>(t[4]), t5 = static_cast<float>(t[5]);
    const float t6 = static_cast<float>(t[6]), t7 = static_cast<float>(t[7]), t8 = static_cast<float>(t[8]);

    const bool isStar = (kind == "star");
    const bool isQuasar = (kind == "quasar");
    const bool isPulsar = (kind == "pulsar");

    if (isStar || isQuasar || isPulsar) {
        const float bodyR = isStar ? 0.90f : (isPulsar ? 0.14f : 0.11f);
        const float bodyR2 = bodyR * bodyR;
        const float invBodyR = 1.0f / bodyR;
        const bool diskVisible = isQuasar && std::abs(t5) >= 0.0001f;
        const float invT5 = diskVisible ? (-1.0f / t5) : 0.0f;
        const float extent = radius * (diskVisible ? 1.0f : bodyR);
        const int start = std::max(0, static_cast<int>(std::floor(center - extent)) - 1);
        const int end = std::min(renderSize - 1, static_cast<int>(std::ceil(center + extent)) + 1);

        for (int row = start; row <= end; ++row) {
            const float sy = (center - row) * invRadius;
            const float sy2 = sy * sy;
            uint8_t* rowPtr = output + static_cast<size_t>(row) * static_cast<size_t>(renderSize) * 4;
            for (int col = start; col <= end; ++col) {
                const float sx = (col - center) * invRadius;
                const float sq = sx * sx + sy2;
                uint8_t* dst = rowPtr + col * 4;
                if (sq < bodyR2) {
                    const float sz = std::sqrt(bodyR2 - sq) * invBodyR;
                    const float sxn = sx * invBodyR;
                    const float syn = sy * invBodyR;
                    const float bx = t0 * sxn + t1 * syn + t2 * sz;
                    const float by = t3 * sxn + t4 * syn + t5 * sz;
                    const float bz = t6 * sxn + t7 * syn + t8 * sz;
                    const float grain = 0.94f + 0.035f * std::sin(bx * 85.0f + std::sin(bz * 47.0f)) * std::sin(by * 73.0f);
                    const float bright = (0.55f + 0.45f * sz) * grain;
                    if (isQuasar) {
                        dst[0] = 2; dst[1] = 2; dst[2] = 2;
                    } else {
                        dst[0] = static_cast<uint8_t>(clampByteF(colR * bright));
                        dst[1] = static_cast<uint8_t>(clampByteF(colG * bright));
                        dst[2] = static_cast<uint8_t>(clampByteF(colB * bright));
                    }
                    const float edge = std::min(1.0f, (bodyR - std::sqrt(sq)) * radius);
                    dst[3] = static_cast<uint8_t>(clampByteF(255.0f * edge));
                }
                if (!diskVisible) continue;
                const float sz = (t3 * sx + t4 * sy) * invT5;
                if (std::abs(sz) > 1.1f) continue;
                const float bx = t0 * sx + t1 * sy + t2 * sz;
                const float bz = t6 * sx + t7 * sy + t8 * sz;
                const float radial = std::sqrt(bx * bx + bz * bz);
                if (radial < 0.15f || radial > 1.0f) continue;
                if (sq < bodyR2 && sz < std::sqrt(bodyR2 - sq)) continue;
                const float heat = std::pow(1.0f - radial, 0.65f);
                const float pattern = 0.86f + 0.14f * std::sin(radial * 95.0f + 6.0f * std::atan2(bz, bx));
                dst[0] = static_cast<uint8_t>(clampByteF(255.0f * pattern));
                dst[1] = static_cast<uint8_t>(clampByteF((85.0f + heat * 170.0f) * pattern));
                dst[2] = static_cast<uint8_t>(clampByteF((28.0f + heat * 175.0f) * pattern));
                dst[3] = static_cast<uint8_t>(clampByteF(255.0f * std::min(1.0f, (1.0f - radial) * 8.0f) * (0.45f + heat * 0.55f)));
            }
        }
    }

    if (partPtr != nullptr && partCount > 0) {
        struct ProjParticle {
            float sx, sy, sz, rad, r, g, b, a;
        };
        std::vector<ProjParticle> proj(partCount);
        for (size_t i = 0; i < partCount; ++i) {
            const float* p = partPtr + i * 8;
            const float px = p[0], py = p[1], pz = p[2];
            proj[i] = {
                t0 * px + t3 * py + t6 * pz,
                t1 * px + t4 * py + t7 * pz,
                t2 * px + t5 * py + t8 * pz,
                p[3], p[4], p[5], p[6], p[7]
            };
        }
        std::sort(proj.begin(), proj.end(), [](const ProjParticle& a, const ProjParticle& b) {
            return a.sz < b.sz;
        });
        for (const auto& pt : proj) {
            if (isPulsar && (pt.sx * pt.sx + pt.sy * pt.sy < 0.14f * 0.14f) && pt.sz < 0.0f) continue;
            const float cx = center + pt.sx * radius;
            const float cy = center - pt.sy * radius;
            const float pr = std::max(0.65f, pt.rad * radius);
            const float invPr2 = 1.0f / std::max(0.2f, pr * pr);
            const float ext = std::max(1.0f, pr * 2.0f);
            const int r0 = std::max(0, static_cast<int>(std::floor(cy - ext)));
            const int r1 = std::min(renderSize - 1, static_cast<int>(std::ceil(cy + ext)));
            const int c0 = std::max(0, static_cast<int>(std::floor(cx - ext)));
            const int c1 = std::min(renderSize - 1, static_cast<int>(std::ceil(cx + ext)));
            for (int row = r0; row <= r1; ++row) {
                const float dy = row - cy;
                const float dy2 = dy * dy;
                uint8_t* rowPtr = output + static_cast<size_t>(row) * static_cast<size_t>(renderSize) * 4;
                for (int col = c0; col <= c1; ++col) {
                    const float dx = col - cx;
                    const float sq = (dx * dx + dy2) * invPr2;
                    if (sq > 4.0f) continue;
                    const float alpha = pt.a * std::exp(-sq * 1.8f);
                    uint8_t* dst = rowPtr + col * 4;
                    const float oldA = dst[3] * kInv255;
                    const float wOld = oldA * (1.0f - alpha);
                    const float comb = alpha + wOld;
                    if (comb <= 0.0f) continue;
                    const float invC = 1.0f / comb;
                    dst[0] = static_cast<uint8_t>(clampByteF((pt.r * alpha + dst[0] * wOld) * invC));
                    dst[1] = static_cast<uint8_t>(clampByteF((pt.g * alpha + dst[1] * wOld) * invC));
                    dst[2] = static_cast<uint8_t>(clampByteF((pt.b * alpha + dst[2] * wOld) * invC));
                    dst[3] = static_cast<uint8_t>(clampByteF(comb * 255.0f));
                }
            }
        }
    }

    return resultAb;
}

// ---------------------------------------------------------------------------
// 3. Constellation 3D Mesh Rasterizer (SCM1 binary format, 82 constellations)
// ---------------------------------------------------------------------------
struct CachedScmMesh {
    uint64_t fingerprint = 0;
    size_t byteLength = 0;
    uint32_t vertexCount = 0;
    uint32_t indexCount = 0;
    // Normalized centered positions & unit normals: 6 floats per vertex
    std::vector<float> vertices;
    std::vector<uint32_t> indices;
};

uint64_t scmFingerprint(const uint8_t* data, size_t len) {
    uint64_t h = static_cast<uint64_t>(len) * 14695981039346656037ULL;
    const size_t probes[6] = {0, 12, len / 4, len / 2, (len * 3) / 4, len > 8 ? len - 8 : 0};
    for (size_t pos : probes) {
        if (pos + 4 <= len) {
            uint32_t v = 0;
            std::memcpy(&v, data + pos, 4);
            h = (h ^ v) * 1099511628211ULL;
        }
    }
    return h;
}

bool parseScmMesh(const uint8_t* data, size_t len, CachedScmMesh& cache) {
    if (!data || len < 12 || len > 4800012) return false;
    if (std::memcmp(data, "SCM1", 4) != 0) return false;

    const uint64_t fp = scmFingerprint(data, len);
    if (cache.byteLength == len && cache.fingerprint == fp && cache.vertexCount > 0) {
        return true;
    }

    uint32_t vc = 0, ic = 0;
    std::memcpy(&vc, data + 4, 4);
    std::memcpy(&ic, data + 8, 4);
    if (vc == 0 || vc > 65535 || ic == 0 || ic > 600000 || (ic % 3) != 0) return false;
    const size_t expectedSize = 12 + static_cast<size_t>(vc) * 24 + static_cast<size_t>(ic) * 4;
    if (len != expectedSize) return false;

    const float* rawVerts = reinterpret_cast<const float*>(data + 12);
    float minX = 1e9f, maxX = -1e9f, minY = 1e9f, maxY = -1e9f, minZ = 1e9f, maxZ = -1e9f;
    for (uint32_t i = 0; i < vc; ++i) {
        const float x = rawVerts[i * 6 + 0];
        const float y = rawVerts[i * 6 + 1];
        const float z = rawVerts[i * 6 + 2];
        if (!std::isfinite(x) || !std::isfinite(y) || !std::isfinite(z)) return false;
        if (x < minX) minX = x; if (x > maxX) maxX = x;
        if (y < minY) minY = y; if (y > maxY) maxY = y;
        if (z < minZ) minZ = z; if (z > maxZ) maxZ = z;
    }
    const float cx = 0.5f * (minX + maxX);
    const float cy = 0.5f * (minY + maxY);
    const float cz = 0.5f * (minZ + maxZ);
    float maxR2 = 1e-6f;
    for (uint32_t i = 0; i < vc; ++i) {
        const float dx = rawVerts[i * 6 + 0] - cx;
        const float dy = rawVerts[i * 6 + 1] - cy;
        const float dz = rawVerts[i * 6 + 2] - cz;
        const float r2 = dx * dx + dy * dy + dz * dz;
        if (r2 > maxR2) maxR2 = r2;
    }
    const float normScale = 0.92f / std::sqrt(maxR2);

    cache.vertices.resize(static_cast<size_t>(vc) * 6);
    for (uint32_t i = 0; i < vc; ++i) {
        const float* src = rawVerts + i * 6;
        float* dst = cache.vertices.data() + i * 6;
        dst[0] = (src[0] - cx) * normScale;
        dst[1] = (src[1] - cy) * normScale;
        dst[2] = (src[2] - cz) * normScale;
        float nx = src[3], ny = src[4], nz = src[5];
        const float nlen = std::sqrt(nx * nx + ny * ny + nz * nz);
        if (nlen > 1e-4f) {
            const float inv = 1.0f / nlen;
            nx *= inv; ny *= inv; nz *= inv;
        } else {
            nx = 0.0f; ny = 0.0f; nz = 1.0f;
        }
        dst[3] = nx; dst[4] = ny; dst[5] = nz;
    }

    cache.indices.resize(ic);
    std::memcpy(cache.indices.data(), data + 12 + static_cast<size_t>(vc) * 24, static_cast<size_t>(ic) * 4);
    for (uint32_t idx : cache.indices) {
        if (idx >= vc) return false;
    }
    cache.vertexCount = vc;
    cache.indexCount = ic;
    cache.byteLength = len;
    cache.fingerprint = fp;
    return true;
}

// Args (4):
// 0: scmBuffer (ArrayBuffer)
// 1: renderSize (int)
// 2: scale (double)
// 3: transform (number[9])
napi_value RenderDetailModelConstellation(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4];
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 4) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    const uint8_t* scmData = nullptr;
    size_t scmLen = 0;
    int32_t renderSize = 0;
    double scale = 1.0;
    double t[9];
    if (!readOptionalArrayBuffer(env, args[0], scmData, scmLen) || scmData == nullptr ||
        !readIntArg(env, args[1], renderSize) ||
        !readDoubleArg(env, args[2], scale) ||
        !readTransform9(env, args[3], t) ||
        renderSize < 16 || renderSize > 1024) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    thread_local CachedScmMesh meshCache;
    if (!parseScmMesh(scmData, scmLen, meshCache)) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    uint8_t* output = nullptr;
    napi_value resultAb = createOutputArrayBuffer(env, renderSize, output);
    if (!resultAb || !output) return nullptr;

    const float center = (renderSize - 1) * 0.5f;
    const float radius = static_cast<float>(renderSize * 0.45 * scale);
    const float t0 = static_cast<float>(t[0]), t1 = static_cast<float>(t[1]), t2 = static_cast<float>(t[2]);
    const float t3 = static_cast<float>(t[3]), t4 = static_cast<float>(t[4]), t5 = static_cast<float>(t[5]);
    const float t6 = static_cast<float>(t[6]), t7 = static_cast<float>(t[7]), t8 = static_cast<float>(t[8]);

    // View-space lighting (key cool starlight + soft warm rim + celestial Fresnel glow)
    const float kLx = -0.44f, kLy = 0.54f, kLz = 0.717f;
    const float fLx = 0.58f, fLy = -0.32f, fLz = 0.748f;

    struct ScreenVertex {
        float sx, sy, sz;
        float r, g, b, a;
    };
    thread_local std::vector<ScreenVertex> screenVerts;
    screenVerts.resize(meshCache.vertexCount);

    const float* vData = meshCache.vertices.data();
    for (uint32_t i = 0; i < meshCache.vertexCount; ++i) {
        const float* v = vData + i * 6;
        const float bx = v[0], by = v[1], bz = v[2];
        const float nx = v[3], ny = v[4], nz = v[5];

        // bodyToView = transform^T (matches ProceduralDetailModel convention)
        const float vx = t0 * bx + t3 * by + t6 * bz;
        const float vy = t1 * bx + t4 * by + t7 * bz;
        const float vz = t2 * bx + t5 * by + t8 * bz;

        // Mild perspective projection for genuine 3D depth cue
        const float persp = 3.2f / (3.2f - vz * 0.65f);
        const float sx = center + vx * radius * persp;
        const float sy = center - vy * radius * persp;

        float vnx = t0 * nx + t3 * ny + t6 * nz;
        float vny = t1 * nx + t4 * ny + t7 * nz;
        float vnz = t2 * nx + t5 * ny + t8 * nz;
        // Two-sided normal so thin silhouettes never vanish when rotated 180 deg
        if (vnz < 0.0f) {
            vnx = -vnx; vny = -vny; vnz = -vnz;
        }

        const float keyDiff = std::max(0.0f, vnx * kLx + vny * kLy + vnz * kLz);
        const float fillDiff = std::max(0.0f, vnx * fLx + vny * fLy + vnz * fLz);
        const float spec = std::pow(std::max(0.0f, vnz * 0.85f + keyDiff * 0.45f - 0.30f), 6.0f);
        const float rim = std::pow(1.0f - std::min(1.0f, vnz), 2.1f);
        const float depthCue = 0.82f + 0.18f * std::max(-1.0f, std::min(1.0f, vz));

        // Luminous celestial-crystal blue-silver sculpture palette
        const float base = (0.14f + 0.56f * keyDiff + 0.18f * fillDiff) * depthCue;
        const float r = std::min(255.0f, (base * 0.64f + rim * 0.48f + spec * 0.42f + fillDiff * 0.08f) * 255.0f);
        const float g = std::min(255.0f, (base * 0.82f + rim * 0.68f + spec * 0.48f) * 255.0f);
        const float b = std::min(255.0f, (base * 1.06f + rim * 0.92f + spec * 0.54f) * 255.0f);
        const float a = std::min(255.0f, (0.86f + 0.14f * rim) * 255.0f);

        screenVerts[i] = {sx, sy, vz, r, g, b, a};
    }

    const size_t pixelCount = static_cast<size_t>(renderSize) * static_cast<size_t>(renderSize);
    thread_local std::vector<float> zbuf;
    zbuf.assign(pixelCount, -1e9f);

    const uint32_t* indices = meshCache.indices.data();
    const uint32_t ic = meshCache.indexCount;
    for (uint32_t i = 0; i + 2 < ic; i += 3) {
        const ScreenVertex& v0 = screenVerts[indices[i]];
        const ScreenVertex& v1 = screenVerts[indices[i + 1]];
        const ScreenVertex& v2 = screenVerts[indices[i + 2]];

        const float area = (v1.sx - v0.sx) * (v2.sy - v0.sy) - (v2.sx - v0.sx) * (v1.sy - v0.sy);
        if (std::abs(area) < 1e-4f) continue;

        const float minXf = std::min({v0.sx, v1.sx, v2.sx});
        const float maxXf = std::max({v0.sx, v1.sx, v2.sx});
        const float minYf = std::min({v0.sy, v1.sy, v2.sy});
        const float maxYf = std::max({v0.sy, v1.sy, v2.sy});

        const int x0 = std::max(0, static_cast<int>(std::floor(minXf)));
        const int x1 = std::min(renderSize - 1, static_cast<int>(std::ceil(maxXf)));
        const int y0 = std::max(0, static_cast<int>(std::floor(minYf)));
        const int y1 = std::min(renderSize - 1, static_cast<int>(std::ceil(maxYf)));
        if (x0 > x1 || y0 > y1) continue;

        const float invArea = 1.0f / area;
        const float e01_dx = v1.sx - v0.sx, e01_dy = v1.sy - v0.sy;
        const float e12_dx = v2.sx - v1.sx, e12_dy = v2.sy - v1.sy;
        const float e20_dx = v0.sx - v2.sx, e20_dy = v0.sy - v2.sy;

        for (int py = y0; py <= y1; ++py) {
            const float fy = static_cast<float>(py) + 0.5f;
            float* zRow = zbuf.data() + static_cast<size_t>(py) * static_cast<size_t>(renderSize);
            uint8_t* outRow = output + static_cast<size_t>(py) * static_cast<size_t>(renderSize) * 4;

            for (int px = x0; px <= x1; ++px) {
                const float fx = static_cast<float>(px) + 0.5f;
                const float w0 = (e12_dx * (fy - v1.sy) - e12_dy * (fx - v1.sx)) * invArea;
                if (w0 < -1e-4f) continue;
                const float w1 = (e20_dx * (fy - v2.sy) - e20_dy * (fx - v2.sx)) * invArea;
                if (w1 < -1e-4f) continue;
                const float w2 = 1.0f - w0 - w1;
                if (w2 < -1e-4f) continue;

                const float z = w0 * v0.sz + w1 * v1.sz + w2 * v2.sz;
                if (z <= zRow[px]) continue;
                zRow[px] = z;

                uint8_t* dst = outRow + px * 4;
                dst[0] = static_cast<uint8_t>(clampByteF(w0 * v0.r + w1 * v1.r + w2 * v2.r));
                dst[1] = static_cast<uint8_t>(clampByteF(w0 * v0.g + w1 * v1.g + w2 * v2.g));
                dst[2] = static_cast<uint8_t>(clampByteF(w0 * v0.b + w1 * v1.b + w2 * v2.b));
                dst[3] = static_cast<uint8_t>(clampByteF(w0 * v0.a + w1 * v1.a + w2 * v2.a));
            }
        }
    }

    return resultAb;
}

// ---------------------------------------------------------------------------
// 4. Real Spacecraft 3D Minor-Body / Irregular Moon Mesh (SBM1 + Optional UV Texture)
// ---------------------------------------------------------------------------
struct CachedSbmMesh {
    uint32_t vertexCount = 0;
    uint32_t indexCount = 0;
    bool hasUV = false;
    float baseColor[3] = {0.72f, 0.70f, 0.68f};
    size_t byteLength = 0;
    uint64_t fingerprint = 0;
    std::vector<float> vertices; // [px, py, pz, nx, ny, nz, u, v] * vertexCount
    std::vector<uint32_t> indices;
};

bool parseSbmMesh(const uint8_t* data, size_t len, CachedSbmMesh& cache) {
    if (!data || len < 28) return false;
    if (data[0] != 'S' || data[1] != 'B' || data[2] != 'M' || data[3] != '1') return false;

    uint64_t fp = static_cast<uint64_t>(len) * 1469598103934665603ULL;
    const size_t step = std::max<size_t>(1, len / 64);
    for (size_t i = 0; i < len; i += step) {
        fp = (fp ^ data[i]) * 1099511628211ULL;
    }
    if (cache.byteLength == len && cache.fingerprint == fp && cache.vertexCount > 0) {
        return true;
    }

    uint32_t vc = 0, ic = 0, flags = 0;
    float bc[3] = {0.72f, 0.70f, 0.68f};
    std::memcpy(&vc, data + 4, 4);
    std::memcpy(&ic, data + 8, 4);
    std::memcpy(&flags, data + 12, 4);
    std::memcpy(bc, data + 16, 12);
    if (vc < 3 || vc > 120000 || ic < 3 || ic > 600000 || (ic % 3) != 0) return false;

    const size_t expectedSize = 28 + static_cast<size_t>(vc) * 32 + static_cast<size_t>(ic) * 4;
    if (len != expectedSize) return false;

    cache.vertices.resize(static_cast<size_t>(vc) * 8);
    std::memcpy(cache.vertices.data(), data + 28, static_cast<size_t>(vc) * 32);
    cache.indices.resize(ic);
    std::memcpy(cache.indices.data(), data + 28 + static_cast<size_t>(vc) * 32, static_cast<size_t>(ic) * 4);
    for (uint32_t idx : cache.indices) {
        if (idx >= vc) return false;
    }

    cache.vertexCount = vc;
    cache.indexCount = ic;
    cache.hasUV = (flags & 1U) != 0;
    cache.baseColor[0] = std::max(0.05f, std::min(1.0f, bc[0]));
    cache.baseColor[1] = std::max(0.05f, std::min(1.0f, bc[1]));
    cache.baseColor[2] = std::max(0.05f, std::min(1.0f, bc[2]));
    cache.byteLength = len;
    cache.fingerprint = fp;
    return true;
}

// Args (12):
// 0: sbmBuffer (ArrayBuffer)
// 1: texture (ArrayBuffer | undefined)
// 2: textureWidth (int)
// 3: textureHeight (int)
// 4: textureStride (int)
// 5: renderSize (int)
// 6: scale (double)
// 7: transform (number[9])
// 8: hasLighting (bool)
// 9: lightX (double)
// 10: lightY (double)
// 11: lightZ (double)
napi_value RenderDetailModelBodyMesh(napi_env env, napi_callback_info info) {
    size_t argc = 12;
    napi_value args[12];
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc < 12) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    const uint8_t* sbmData = nullptr;
    size_t sbmLen = 0;
    const uint8_t* texData = nullptr;
    size_t texLen = 0;
    int32_t texW = 0, texH = 0, texStride = 0, renderSize = 0;
    double scale = 1.0;
    double t[9];
    bool hasLighting = false;
    double lightX = -0.45, lightY = 0.45, lightZ = 0.77;

    if (!readOptionalArrayBuffer(env, args[0], sbmData, sbmLen) || sbmData == nullptr ||
        !readOptionalArrayBuffer(env, args[1], texData, texLen) ||
        !readIntArg(env, args[2], texW) || !readIntArg(env, args[3], texH) || !readIntArg(env, args[4], texStride) ||
        !readIntArg(env, args[5], renderSize) || !readDoubleArg(env, args[6], scale) ||
        !readTransform9(env, args[7], t) || !readBoolArg(env, args[8], hasLighting) ||
        !readDoubleArg(env, args[9], lightX) || !readDoubleArg(env, args[10], lightY) || !readDoubleArg(env, args[11], lightZ) ||
        renderSize < 16 || renderSize > 1024) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    thread_local CachedSbmMesh meshCache;
    if (!parseSbmMesh(sbmData, sbmLen, meshCache)) {
        napi_value undef = nullptr;
        napi_get_undefined(env, &undef);
        return undef;
    }

    const bool useTexture = meshCache.hasUV && texData != nullptr && texW > 0 && texH > 0 &&
                            texStride >= texW * 4 && texLen >= static_cast<size_t>(texStride) * static_cast<size_t>(texH);

    uint8_t* output = nullptr;
    napi_value resultAb = createOutputArrayBuffer(env, renderSize, output);
    if (!resultAb || !output) return nullptr;

    const float center = (renderSize - 1) * 0.5f;
    const float radius = static_cast<float>(renderSize * 0.43 * scale);
    const float t0 = static_cast<float>(t[0]), t1 = static_cast<float>(t[1]), t2 = static_cast<float>(t[2]);
    const float t3 = static_cast<float>(t[3]), t4 = static_cast<float>(t[4]), t5 = static_cast<float>(t[5]);
    const float t6 = static_cast<float>(t[6]), t7 = static_cast<float>(t[7]), t8 = static_cast<float>(t[8]);

    // Transform solar illumination vector into view space (or use crisp 3/4 studio key light)
    float lx = -0.45f, ly = 0.42f, lz = 0.788f;
    if (hasLighting) {
        const float slx = static_cast<float>(lightX);
        const float sly = static_cast<float>(lightY);
        const float slz = static_cast<float>(lightZ);
        float vlx = t0 * slx + t3 * sly + t6 * slz;
        float vly = t1 * slx + t4 * sly + t7 * slz;
        float vlz = t2 * slx + t5 * sly + t8 * slz;
        const float ll = std::sqrt(vlx * vlx + vly * vly + vlz * vlz);
        if (ll > 1e-4f) {
            // Blend 75% real solar phase with 25% front key so dark silhouettes stay sculpturally legible
            vlx = vlx / ll * 0.78f + (-0.30f) * 0.22f;
            vly = vly / ll * 0.78f + (0.28f) * 0.22f;
            vlz = vlz / ll * 0.78f + (0.91f) * 0.22f;
            const float bl = std::sqrt(vlx * vlx + vly * vly + vlz * vlz);
            if (bl > 1e-4f) {
                lx = vlx / bl; ly = vly / bl; lz = vlz / bl;
            }
        }
    }

    struct BodyScreenVertex {
        float sx, sy, sz;
        float u, v;
        float shade;
        float rim;
    };
    thread_local std::vector<BodyScreenVertex> screenVerts;
    screenVerts.resize(meshCache.vertexCount);

    const float* vData = meshCache.vertices.data();
    for (uint32_t i = 0; i < meshCache.vertexCount; ++i) {
        const float* v = vData + i * 8;
        const float bx = v[0], by = v[1], bz = v[2];
        const float nx = v[3], ny = v[4], nz = v[5];

        const float vx = t0 * bx + t3 * by + t6 * bz;
        const float vy = t1 * bx + t4 * by + t7 * bz;
        const float vz = t2 * bx + t5 * by + t8 * bz;

        const float persp = 3.4f / (3.4f - vz * 0.65f);
        const float sx = center + vx * radius * persp;
        const float sy = center - vy * radius * persp;

        float vnx = t0 * nx + t3 * ny + t6 * nz;
        float vny = t1 * nx + t4 * ny + t7 * nz;
        float vnz = t2 * nx + t5 * ny + t8 * nz;
        const float nlen = std::sqrt(vnx * vnx + vny * vny + vnz * vnz);
        if (nlen > 1e-4f) {
            const float inv = 1.0f / nlen;
            vnx *= inv; vny *= inv; vnz *= inv;
        }
        if (vnz < 0.0f) {
            vnx = -vnx; vny = -vny; vnz = -vnz;
        }

        // Lommel-Seeliger + Lambert rocky regolith shading for realistic asteroids & comets
        const float ndotl = std::max(0.0f, vnx * lx + vny * ly + vnz * lz);
        const float ndotv = std::max(0.05f, vnz);
        const float lommel = ndotl / (ndotl + ndotv + 0.16f);
        const float fill = std::max(0.0f, vnx * 0.45f - vny * 0.35f + vnz * 0.82f) * 0.14f;
        const float shade = 0.16f + 0.64f * ndotl + 0.44f * lommel + fill;
        const float rim = std::pow(1.0f - std::min(1.0f, vnz), 2.4f) * (0.12f + 0.24f * ndotl);

        screenVerts[i] = {sx, sy, vz, v[6], v[7], shade, rim};
    }

    const size_t pixelCount = static_cast<size_t>(renderSize) * static_cast<size_t>(renderSize);
    thread_local std::vector<float> zbuf;
    zbuf.assign(pixelCount, -1e9f);

    const float baseR = meshCache.baseColor[0] * 255.0f;
    const float baseG = meshCache.baseColor[1] * 255.0f;
    const float baseB = meshCache.baseColor[2] * 255.0f;

    const uint32_t* indices = meshCache.indices.data();
    const uint32_t ic = meshCache.indexCount;
    for (uint32_t i = 0; i + 2 < ic; i += 3) {
        const BodyScreenVertex& v0 = screenVerts[indices[i]];
        const BodyScreenVertex& v1 = screenVerts[indices[i + 1]];
        const BodyScreenVertex& v2 = screenVerts[indices[i + 2]];

        const float area = (v1.sx - v0.sx) * (v2.sy - v0.sy) - (v2.sx - v0.sx) * (v1.sy - v0.sy);
        if (std::abs(area) < 1e-4f) continue;

        const float minXf = std::min({v0.sx, v1.sx, v2.sx});
        const float maxXf = std::max({v0.sx, v1.sx, v2.sx});
        const float minYf = std::min({v0.sy, v1.sy, v2.sy});
        const float maxYf = std::max({v0.sy, v1.sy, v2.sy});

        const int x0 = std::max(0, static_cast<int>(std::floor(minXf)));
        const int x1 = std::min(renderSize - 1, static_cast<int>(std::ceil(maxXf)));
        const int y0 = std::max(0, static_cast<int>(std::floor(minYf)));
        const int y1 = std::min(renderSize - 1, static_cast<int>(std::ceil(maxYf)));
        if (x0 > x1 || y0 > y1) continue;

        const float invArea = 1.0f / area;
        const float e01_dx = v1.sx - v0.sx, e01_dy = v1.sy - v0.sy;
        const float e12_dx = v2.sx - v1.sx, e12_dy = v2.sy - v1.sy;
        const float e20_dx = v0.sx - v2.sx, e20_dy = v0.sy - v2.sy;

        for (int py = y0; py <= y1; ++py) {
            const float fy = static_cast<float>(py) + 0.5f;
            float* zRow = zbuf.data() + static_cast<size_t>(py) * static_cast<size_t>(renderSize);
            uint8_t* outRow = output + static_cast<size_t>(py) * static_cast<size_t>(renderSize) * 4;

            for (int px = x0; px <= x1; ++px) {
                const float fx = static_cast<float>(px) + 0.5f;
                const float w0 = (e12_dx * (fy - v1.sy) - e12_dy * (fx - v1.sx)) * invArea;
                if (w0 < -1e-4f) continue;
                const float w1 = (e20_dx * (fy - v2.sy) - e20_dy * (fx - v2.sx)) * invArea;
                if (w1 < -1e-4f) continue;
                const float w2 = 1.0f - w0 - w1;
                if (w2 < -1e-4f) continue;

                const float z = w0 * v0.sz + w1 * v1.sz + w2 * v2.sz;
                if (z <= zRow[px]) continue;
                zRow[px] = z;

                const float shade = w0 * v0.shade + w1 * v1.shade + w2 * v2.shade;
                const float rim = w0 * v0.rim + w1 * v1.rim + w2 * v2.rim;

                float tr = baseR, tg = baseG, tb = baseB;
                if (useTexture) {
                    float u = w0 * v0.u + w1 * v1.u + w2 * v2.u;
                    float v = w0 * v0.v + w1 * v1.v + w2 * v2.v;
                    u = u - std::floor(u);
                    v = std::max(0.0f, std::min(0.9999f, v));
                    const int tx = std::min(texW - 1, std::max(0, static_cast<int>(u * texW)));
                    const int ty = std::min(texH - 1, std::max(0, static_cast<int>(v * texH)));
                    const uint8_t* texPx = texData + static_cast<size_t>(ty) * static_cast<size_t>(texStride) + static_cast<size_t>(tx) * 4;
                    tr = static_cast<float>(texPx[0]);
                    tg = static_cast<float>(texPx[1]);
                    tb = static_cast<float>(texPx[2]);
                    // Fill un-imaged spacecraft polar gaps (e.g. Dawn Vesta winter pole) with subtle rocky base albedo
                    if (tr + tg + tb < 12.0f) {
                        tr = baseR * 0.58f;
                        tg = baseG * 0.58f;
                        tb = baseB * 0.58f;
                    }
                }

                uint8_t* dst = outRow + px * 4;
                dst[0] = static_cast<uint8_t>(clampByteF(tr * shade + rim * 165.0f));
                dst[1] = static_cast<uint8_t>(clampByteF(tg * shade + rim * 175.0f));
                dst[2] = static_cast<uint8_t>(clampByteF(tb * shade + rim * 195.0f));
                dst[3] = 255;
            }
        }
    }

    return resultAb;
}

} // namespace

void registerDetailModelNapi(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        { "renderDetailModelSphere", nullptr, RenderDetailModelSphere, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "renderDetailModelProcedural", nullptr, RenderDetailModelProcedural, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "renderDetailModelConstellation", nullptr, RenderDetailModelConstellation, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "renderDetailModelBodyMesh", nullptr, RenderDetailModelBodyMesh, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
}
