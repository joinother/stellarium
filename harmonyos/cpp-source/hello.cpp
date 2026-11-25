// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

#include "napi/native_api.h"
#include "PresentationGeometry.h"
#include "DetailModelNative.h"

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <GLES2/gl2ext.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <hilog/log.h>
#include <native_image/native_image.h>

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <condition_variable>
#include <cstddef>
#include <cstdlib>
#include <dlfcn.h>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr unsigned int STEL_ENTRY_LOG_DOMAIN = 0x0000;
constexpr const char* STEL_ENTRY_LOG_TAG = "StellariumEntryGL";
using StellariumCommandFunc = const char* (*)(const char*, const char*);

struct EglState
{
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLConfig config = nullptr;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    int width = 0;
    int height = 0;
    GLuint starProgram = 0;
    GLuint starBuffer = 0;
    GLuint frameProgram = 0;
    GLuint frameTexture = 0;
    GLuint arCompositeProgram = 0;
    GLuint arCameraTexture = 0;
    GLuint lastSkyTexture = 0;
    int lastSkyWidth = 0;
    int lastSkyHeight = 0;
    float lastSkyFovDeg = 0.0f;
    int frameTextureWidth = 0;
    int frameTextureHeight = 0;
    bool submittedFrame = false;
    bool sharedTextureContext = false;
    bool zeroCopyUnavailable = false;
};

struct ArCameraState
{
    OH_NativeImage* image = nullptr;
    uint64_t surfaceId = 0;
    bool attachPending = false;
    bool destroyPending = false;
    bool hasFrame = false;
    bool compositeEnabled = false;
    float skyBlend = 0.55f;
    float cameraAspect = 16.0f / 9.0f;
    float baseFovDeg = 45.0f;
    float transform[16] = {
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, 0.0f, 1.0f
    };
};

EglState g_egl;
ArCameraState g_ar;
std::atomic<float> g_renderedFovDeg {0.0f};
std::atomic<bool> g_arFrameAvailable {false};
std::mutex g_arWakeMutex;
std::condition_variable g_arWakeCv;
std::atomic<bool> g_arPresentThreadStarted {false};
OH_NativeXComponent_Callback g_xcomponentCallback;
std::mutex g_renderMutex;
std::atomic<std::uint64_t> g_presentationState {0};

void onArCameraFrameAvailable(void*)
{
    g_arFrameAvailable.store(true, std::memory_order_release);
    g_arWakeCv.notify_one();
}

struct StarVertex
{
    float x;
    float y;
    float size;
    float brightness;
};

constexpr std::array<StarVertex, 96> STARS = {{
    {-0.94f, 0.82f, 4.0f, 0.65f}, {-0.86f, 0.55f, 3.0f, 0.78f}, {-0.79f, 0.21f, 5.0f, 0.92f},
    {-0.72f, 0.68f, 2.5f, 0.52f}, {-0.66f, -0.18f, 4.5f, 0.86f}, {-0.61f, -0.62f, 3.0f, 0.60f},
    {-0.54f, 0.37f, 6.0f, 1.00f}, {-0.48f, -0.04f, 2.5f, 0.55f}, {-0.42f, 0.76f, 3.5f, 0.72f},
    {-0.36f, -0.41f, 5.0f, 0.88f}, {-0.29f, 0.09f, 3.0f, 0.66f}, {-0.23f, -0.74f, 4.0f, 0.80f},
    {-0.16f, 0.48f, 2.0f, 0.58f}, {-0.10f, -0.10f, 6.0f, 0.96f}, {-0.04f, 0.88f, 3.0f, 0.62f},
    {0.03f, -0.55f, 4.5f, 0.82f}, {0.09f, 0.31f, 3.0f, 0.68f}, {0.15f, -0.84f, 2.5f, 0.50f},
    {0.22f, 0.69f, 5.5f, 0.95f}, {0.28f, -0.22f, 3.5f, 0.70f}, {0.35f, 0.03f, 2.5f, 0.56f},
    {0.41f, -0.67f, 4.5f, 0.84f}, {0.48f, 0.43f, 3.0f, 0.63f}, {0.55f, 0.84f, 5.0f, 0.90f},
    {0.62f, -0.36f, 2.5f, 0.58f}, {0.69f, 0.17f, 6.5f, 1.00f}, {0.76f, -0.80f, 3.0f, 0.64f},
    {0.83f, 0.58f, 4.0f, 0.82f}, {0.90f, -0.07f, 2.5f, 0.54f}, {0.96f, 0.29f, 5.0f, 0.89f},
    {-0.97f, -0.31f, 2.0f, 0.52f}, {-0.91f, -0.88f, 3.0f, 0.69f}, {-0.84f, -0.03f, 4.0f, 0.80f},
    {-0.77f, -0.51f, 2.5f, 0.57f}, {-0.70f, 0.02f, 3.0f, 0.61f}, {-0.63f, 0.91f, 4.5f, 0.87f},
    {-0.57f, -0.77f, 3.5f, 0.73f}, {-0.50f, 0.60f, 2.5f, 0.56f}, {-0.44f, -0.20f, 5.0f, 0.91f},
    {-0.38f, 0.18f, 2.0f, 0.50f}, {-0.31f, 0.82f, 3.5f, 0.76f}, {-0.25f, -0.03f, 4.0f, 0.78f},
    {-0.18f, -0.56f, 2.5f, 0.58f}, {-0.12f, 0.20f, 3.0f, 0.66f}, {-0.06f, -0.91f, 5.5f, 0.94f},
    {0.00f, 0.57f, 2.5f, 0.59f}, {0.06f, -0.31f, 4.0f, 0.77f}, {0.13f, 0.05f, 3.0f, 0.64f},
    {0.20f, -0.47f, 2.0f, 0.52f}, {0.27f, 0.91f, 4.5f, 0.86f}, {0.33f, 0.24f, 3.0f, 0.67f},
    {0.39f, -0.03f, 5.0f, 0.92f}, {0.46f, -0.93f, 3.0f, 0.65f}, {0.53f, -0.14f, 2.5f, 0.56f},
    {0.59f, 0.68f, 4.0f, 0.79f}, {0.66f, -0.55f, 2.0f, 0.51f}, {0.73f, 0.88f, 3.5f, 0.74f},
    {0.80f, -0.28f, 4.5f, 0.85f}, {0.87f, 0.02f, 3.0f, 0.63f}, {0.94f, -0.58f, 5.5f, 0.93f},
    {-0.88f, 0.34f, 2.0f, 0.48f}, {-0.81f, 0.74f, 3.0f, 0.71f}, {-0.74f, -0.72f, 4.0f, 0.79f},
    {-0.67f, 0.47f, 2.5f, 0.57f}, {-0.60f, -0.34f, 3.5f, 0.75f}, {-0.53f, 0.05f, 2.0f, 0.51f},
    {-0.46f, 0.95f, 5.0f, 0.90f}, {-0.39f, -0.86f, 3.0f, 0.68f}, {-0.32f, 0.53f, 2.5f, 0.55f},
    {-0.25f, -0.28f, 4.0f, 0.81f}, {-0.18f, 0.74f, 3.5f, 0.76f}, {-0.11f, -0.68f, 2.0f, 0.50f},
    {-0.04f, 0.12f, 4.5f, 0.84f}, {0.03f, 0.79f, 2.5f, 0.58f}, {0.10f, -0.73f, 3.0f, 0.67f},
    {0.17f, 0.54f, 5.0f, 0.88f}, {0.24f, -0.08f, 2.0f, 0.53f}, {0.31f, -0.61f, 3.5f, 0.72f},
    {0.38f, 0.73f, 2.5f, 0.57f}, {0.45f, 0.15f, 4.0f, 0.79f}, {0.52f, -0.43f, 3.0f, 0.65f},
    {0.59f, 0.33f, 2.0f, 0.51f}, {0.66f, -0.11f, 5.0f, 0.91f}, {0.73f, -0.69f, 2.5f, 0.56f},
    {0.80f, 0.42f, 3.5f, 0.73f}, {0.87f, -0.90f, 4.0f, 0.80f}, {0.94f, 0.75f, 3.0f, 0.66f},
    {-0.95f, 0.04f, 3.5f, 0.73f}, {-0.52f, -0.56f, 2.0f, 0.50f}, {-0.09f, 0.66f, 4.0f, 0.83f},
    {0.34f, -0.79f, 2.5f, 0.55f}, {0.71f, 0.61f, 3.5f, 0.72f}, {0.98f, -0.18f, 2.0f, 0.51f}
}};

GLuint compileShader(GLenum type, const char* source)
{
    const GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);

    GLint ok = GL_FALSE;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (ok != GL_TRUE) {
        char log[512] = {};
        glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "shader compile failed: %{public}s", log);
        glDeleteShader(shader);
        return 0;
    }

    return shader;
}

GLuint createStarProgram()
{
    constexpr const char* vertexShader = R"(#version 300 es
layout(location = 0) in vec2 a_position;
layout(location = 1) in float a_size;
layout(location = 2) in float a_brightness;
out float v_brightness;
void main()
{
    gl_Position = vec4(a_position, 0.0, 1.0);
    gl_PointSize = a_size;
    v_brightness = a_brightness;
})";

    constexpr const char* fragmentShader = R"(#version 300 es
precision mediump float;
in float v_brightness;
out vec4 fragColor;
void main()
{
    vec2 point = gl_PointCoord * 2.0 - 1.0;
    float distanceSq = dot(point, point);
    if (distanceSq > 1.0) {
        discard;
    }
    float halo = 1.0 - smoothstep(0.08, 1.0, distanceSq);
    vec3 color = mix(vec3(0.58, 0.74, 1.0), vec3(1.0, 0.96, 0.82), v_brightness);
    fragColor = vec4(color * v_brightness, halo);
})";

    const GLuint vs = compileShader(GL_VERTEX_SHADER, vertexShader);
    const GLuint fs = compileShader(GL_FRAGMENT_SHADER, fragmentShader);
    if (vs == 0 || fs == 0) {
        glDeleteShader(vs);
        glDeleteShader(fs);
        return 0;
    }

    const GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);
    glDeleteShader(vs);
    glDeleteShader(fs);

    GLint ok = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (ok != GL_TRUE) {
        char log[512] = {};
        glGetProgramInfoLog(program, sizeof(log), nullptr, log);
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "program link failed: %{public}s", log);
        glDeleteProgram(program);
        return 0;
    }

    return program;
}

GLuint createFrameProgram()
{
    constexpr const char* vertexShader = R"(#version 300 es
out vec2 v_texCoord;
void main()
{
    vec2 position = vec2(-1.0, -1.0);
    vec2 texCoord = vec2(0.0, 0.0);
    if (gl_VertexID == 1) {
        position = vec2(3.0, -1.0);
        texCoord = vec2(2.0, 0.0);
    } else if (gl_VertexID == 2) {
        position = vec2(-1.0, 3.0);
        texCoord = vec2(0.0, 2.0);
    }
    gl_Position = vec4(position, 0.0, 1.0);
    v_texCoord = texCoord;
})";

    constexpr const char* fragmentShader = R"(#version 300 es
precision mediump float;
uniform sampler2D u_frame;
in vec2 v_texCoord;
out vec4 fragColor;
void main()
{
    fragColor = texture(u_frame, v_texCoord);
})";

    const GLuint vs = compileShader(GL_VERTEX_SHADER, vertexShader);
    const GLuint fs = compileShader(GL_FRAGMENT_SHADER, fragmentShader);
    if (vs == 0 || fs == 0) {
        glDeleteShader(vs);
        glDeleteShader(fs);
        return 0;
    }

    const GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);
    glDeleteShader(vs);
    glDeleteShader(fs);

    GLint ok = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (ok != GL_TRUE) {
        char log[512] = {};
        glGetProgramInfoLog(program, sizeof(log), nullptr, log);
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "frame program link failed: %{public}s", log);
        glDeleteProgram(program);
        return 0;
    }

    return program;
}

GLuint createArCompositeProgram()
{
    constexpr const char* vertexShader = R"(#version 300 es
out vec2 v_texCoord;
void main()
{
    vec2 position = vec2(-1.0, -1.0);
    vec2 texCoord = vec2(0.0, 0.0);
    if (gl_VertexID == 1) {
        position = vec2(3.0, -1.0);
        texCoord = vec2(2.0, 0.0);
    } else if (gl_VertexID == 2) {
        position = vec2(-1.0, 3.0);
        texCoord = vec2(0.0, 2.0);
    }
    gl_Position = vec4(position, 0.0, 1.0);
    v_texCoord = texCoord;
})";

    constexpr const char* fragmentShader = R"(#version 300 es
#extension GL_OES_EGL_image_external_essl3 : require
precision mediump float;
uniform sampler2D u_frame;
uniform samplerExternalOES u_camera;
uniform mat4 u_camTransform;
uniform float u_blend;
uniform float u_screenAspect;
uniform float u_cameraAspect;
uniform float u_cameraZoom;
in vec2 v_texCoord;
out vec4 fragColor;
void main()
{
    vec2 cropUv = v_texCoord;
    if (u_screenAspect > 0.01 && u_cameraAspect > 0.01) {
        if (u_screenAspect > u_cameraAspect) {
            float scaleY = u_cameraAspect / u_screenAspect;
            cropUv.y = (cropUv.y - 0.5) * scaleY + 0.5;
        } else {
            float scaleX = u_screenAspect / u_cameraAspect;
            cropUv.x = (cropUv.x - 0.5) * scaleX + 0.5;
        }
    }
    float zoom = max(0.25, u_cameraZoom);
    cropUv = (cropUv - 0.5) / zoom + 0.5;
    float edgeMargin = min(min(cropUv.x, 1.0 - cropUv.x), min(cropUv.y, 1.0 - cropUv.y));
    float camBounds = smoothstep(-0.015, 0.015, edgeMargin);
    vec2 camUv = clamp((u_camTransform * vec4(clamp(cropUv, vec2(0.0), vec2(1.0)), 0.0, 1.0)).xy, vec2(0.0), vec2(1.0));
    vec3 cam = texture(u_camera, camUv).rgb;
    vec3 sky = texture(u_frame, v_texCoord).rgb;

    float b = clamp(u_blend, 0.0, 1.0);
    // 1080p pixel-level Sky Luminance Keying (auto-cuts out dark trees, leaves, roofs, buildings):
    // Sky pixels have higher luminance (and cool/blue chroma bias outdoors) than silhouetted foreground.
    float camLuma = dot(cam, vec3(0.2126, 0.7152, 0.0722));
    float blueBias = max(0.0, cam.b - max(cam.r, cam.g)) * 0.28;
    float skySignal = clamp(camLuma + blueBias, 0.0, 1.0);

    // b in [0.02..0.90] sweeps the sky-vs-foreground luminance cutoff from bright sky (0.88) down to dim twilight (0.06).
    float keyRange = clamp(b / 0.90, 0.0, 1.0);
    float cutPoint = mix(0.88, 0.06, keyRange);
    float feather = 0.085;
    float skyMask = smoothstep(cutPoint - feather, cutPoint + feather, skySignal) * smoothstep(0.0, 0.04, b);

    // Inside keyed sky region: smoothly darken bright real sky and fuse deep crisp stars, constellations & labels.
    vec3 skyBackdrop = cam * mix(0.22, 0.08, keyRange);
    vec3 skyGlow = 1.0 - (1.0 - skyBackdrop) * (1.0 - clamp(sky * 1.18, 0.0, 1.0));
    float skyPeak = max(sky.r, max(sky.g, sky.b));
    vec3 skyRegion = mix(skyGlow, max(skyGlow, sky), smoothstep(0.05, 0.30, skyPeak) * 0.65);

    // Foreground (trees, leaves, buildings where skyMask -> 0) stays 100% real camera occluding the stars!
    vec3 keyedResult = mix(cam, skyRegion, skyMask);

    // Pitch-black rural night fallback (b > 0.90 -> 1.0): smoothly crossfade to full-screen night star overlay.
    float nightOverlayMix = smoothstep(0.90, 1.0, b);
    vec3 nightOverlay = 1.0 - (1.0 - cam * 0.35) * (1.0 - clamp(sky * 1.18, 0.0, 1.0));
    nightOverlay = mix(nightOverlay, max(nightOverlay, sky), smoothstep(0.05, 0.30, skyPeak) * 0.65);
    vec3 fusedRgb = mix(keyedResult, nightOverlay, nightOverlayMix);
    vec3 finalRgb = mix(sky, fusedRgb, camBounds);
    fragColor = vec4(finalRgb, 1.0);
})";

    const GLuint vs = compileShader(GL_VERTEX_SHADER, vertexShader);
    const GLuint fs = compileShader(GL_FRAGMENT_SHADER, fragmentShader);
    if (vs == 0 || fs == 0) {
        glDeleteShader(vs);
        glDeleteShader(fs);
        return 0;
    }

    const GLuint program = glCreateProgram();
    glAttachShader(program, vs);
    glAttachShader(program, fs);
    glLinkProgram(program);
    glDeleteShader(vs);
    glDeleteShader(fs);

    GLint ok = GL_FALSE;
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (ok != GL_TRUE) {
        char log[512] = {};
        glGetProgramInfoLog(program, sizeof(log), nullptr, log);
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "ar composite program link failed: %{public}s", log);
        glDeleteProgram(program);
        return 0;
    }

    return program;
}

void cleanupArCameraGlResourcesLocked()
{
    if (g_ar.image != nullptr) {
        OH_NativeImage_UnsetOnFrameAvailableListener(g_ar.image);
        OH_NativeImage_DetachContext(g_ar.image);
        OH_NativeImage_Destroy(&g_ar.image);
    }
    if (g_egl.arCameraTexture != 0) {
        glDeleteTextures(1, &g_egl.arCameraTexture);
        g_egl.arCameraTexture = 0;
    }
    g_ar.surfaceId = 0;
    g_ar.attachPending = false;
    g_ar.destroyPending = false;
    g_ar.hasFrame = false;
    g_ar.compositeEnabled = false;
    g_arFrameAvailable.store(false, std::memory_order_release);
}

void drawSkyWithOptionalArCameraLocked(GLuint skyTexture, int viewportWidth, int viewportHeight)
{
    if (g_ar.destroyPending) {
        cleanupArCameraGlResourcesLocked();
    } else if (g_ar.compositeEnabled && g_ar.image != nullptr) {
        if (g_ar.attachPending) {
            if (g_egl.arCameraTexture == 0) {
                glGenTextures(1, &g_egl.arCameraTexture);
            }
            glActiveTexture(GL_TEXTURE1);
            glBindTexture(GL_TEXTURE_EXTERNAL_OES, g_egl.arCameraTexture);
            glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_EXTERNAL_OES, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            const int32_t attachRet = OH_NativeImage_AttachContext(g_ar.image, g_egl.arCameraTexture);
            if (attachRet == 0) {
                g_ar.attachPending = false;
                OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                             "[ar-camera] attached native image to OES texture=%{public}u", g_egl.arCameraTexture);
            } else {
                OH_LOG_Print(LOG_APP, LOG_WARN, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                             "[ar-camera] attach context failed ret=%{public}d", attachRet);
            }
        }
        if (!g_ar.attachPending && g_arFrameAvailable.exchange(false, std::memory_order_acquire)) {
            const int32_t updateRet = OH_NativeImage_UpdateSurfaceImage(g_ar.image);
            if (updateRet == 0) {
                if (OH_NativeImage_GetTransformMatrixV2(g_ar.image, g_ar.transform) != 0) {
                    OH_NativeImage_GetTransformMatrix(g_ar.image, g_ar.transform);
                }
                if (!g_ar.hasFrame) {
                    OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                                 "[ar-camera] first camera frame latched for GPU sky fusion");
                }
                g_ar.hasFrame = true;
            }
        }
    }

    if (g_ar.compositeEnabled && g_ar.hasFrame && g_egl.arCameraTexture != 0) {
        if (g_egl.arCompositeProgram == 0) {
            g_egl.arCompositeProgram = createArCompositeProgram();
        }
        if (g_egl.arCompositeProgram != 0) {
            glUseProgram(g_egl.arCompositeProgram);
            glActiveTexture(GL_TEXTURE0);
            glBindTexture(GL_TEXTURE_2D, skyTexture);
            glUniform1i(glGetUniformLocation(g_egl.arCompositeProgram, "u_frame"), 0);
            glActiveTexture(GL_TEXTURE1);
            glBindTexture(GL_TEXTURE_EXTERNAL_OES, g_egl.arCameraTexture);
            glUniform1i(glGetUniformLocation(g_egl.arCompositeProgram, "u_camera"), 1);
            glUniformMatrix4fv(glGetUniformLocation(g_egl.arCompositeProgram, "u_camTransform"), 1, GL_FALSE, g_ar.transform);
            glUniform1f(glGetUniformLocation(g_egl.arCompositeProgram, "u_blend"), g_ar.skyBlend);
            const float screenAspect = (viewportHeight > 0)
                ? static_cast<float>(viewportWidth) / static_cast<float>(viewportHeight)
                : 1.0f;
            glUniform1f(glGetUniformLocation(g_egl.arCompositeProgram, "u_screenAspect"), screenAspect);
            glUniform1f(glGetUniformLocation(g_egl.arCompositeProgram, "u_cameraAspect"), g_ar.cameraAspect);
            float effectiveZoom = 1.0f;
            const float skyFov = g_egl.lastSkyFovDeg > 0.1f
                ? g_egl.lastSkyFovDeg
                : g_renderedFovDeg.load(std::memory_order_acquire);
            if (g_ar.baseFovDeg >= 15.0f && g_ar.baseFovDeg <= 100.0f &&
                skyFov >= 1.0f && skyFov <= 160.0f) {
                const double baseHalfRad = static_cast<double>(g_ar.baseFovDeg) * 0.5 * (3.14159265358979323846 / 180.0);
                const double curHalfRad = static_cast<double>(skyFov) * 0.5 * (3.14159265358979323846 / 180.0);
                const double tanCur = std::tan(curHalfRad);
                if (tanCur > 1e-5) {
                    const double pinholeZoom = std::tan(baseHalfRad) / tanCur;
                    if (std::isfinite(pinholeZoom) && pinholeZoom > 0.0) {
                        effectiveZoom = static_cast<float>(std::max(0.25, std::min(12.0, pinholeZoom)));
                    }
                }
            }
            glUniform1f(glGetUniformLocation(g_egl.arCompositeProgram, "u_cameraZoom"), effectiveZoom);
            glDrawArrays(GL_TRIANGLES, 0, 3);
            glActiveTexture(GL_TEXTURE0);
            return;
        }
    }

    glUseProgram(g_egl.frameProgram);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, skyTexture);
    glUniform1i(glGetUniformLocation(g_egl.frameProgram, "u_frame"), 0);
    glDrawArrays(GL_TRIANGLES, 0, 3);
}

// Camera-driven immediate compositor loop: whenever CameraKit delivers a new frame
// (native 30fps), immediately re-composite it with the latest shared Stellarium sky
// texture without waiting for Stellarium's next heavy Qt frame (~46ms).
void ensureArCameraPresentThreadStarted()
{
    bool expected = false;
    if (!g_arPresentThreadStarted.compare_exchange_strong(expected, true)) {
        return;
    }
    std::thread([]() {
        while (true) {
            {
                std::unique_lock<std::mutex> wakeLock(g_arWakeMutex);
                g_arWakeCv.wait(wakeLock, []() {
                    return g_arFrameAvailable.load(std::memory_order_acquire);
                });
            }
            std::lock_guard<std::mutex> lock(g_renderMutex);
            if (!g_ar.compositeEnabled || g_ar.destroyPending || g_ar.image == nullptr) {
                g_arFrameAvailable.store(false, std::memory_order_release);
                continue;
            }
            if (!g_arFrameAvailable.load(std::memory_order_acquire)) {
                continue;
            }
            if (g_egl.display == EGL_NO_DISPLAY || g_egl.surface == EGL_NO_SURFACE ||
                g_egl.context == EGL_NO_CONTEXT || g_egl.lastSkyTexture == 0 ||
                g_egl.lastSkyWidth <= 0 || g_egl.lastSkyHeight <= 0) {
                continue;
            }
            if (eglMakeCurrent(g_egl.display, g_egl.surface, g_egl.surface, g_egl.context) != EGL_TRUE) {
                continue;
            }
            if (g_egl.frameProgram == 0) {
                g_egl.frameProgram = createFrameProgram();
            }
            if (g_egl.frameProgram != 0) {
                glDisable(GL_SCISSOR_TEST);
                glDisable(GL_DEPTH_TEST);
                glDisable(GL_STENCIL_TEST);
                glDisable(GL_BLEND);
                const auto viewport = fitPresentationFrame(g_egl.lastSkyWidth, g_egl.lastSkyHeight,
                    g_egl.width > 0 ? g_egl.width : g_egl.lastSkyWidth,
                    g_egl.height > 0 ? g_egl.height : g_egl.lastSkyHeight);
                glViewport(viewport.left, viewport.bottom, viewport.width, viewport.height);
                glClearColor(0.f, 0.f, 0.f, 1.f);
                glClear(GL_COLOR_BUFFER_BIT);
                drawSkyWithOptionalArCameraLocked(g_egl.lastSkyTexture, viewport.width, viewport.height);
                eglSwapBuffers(g_egl.display, g_egl.surface);
            }
            eglMakeCurrent(g_egl.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        }
    }).detach();
}

bool initEgl(void* window)
{
    g_egl.display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (g_egl.display == EGL_NO_DISPLAY) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG, "eglGetDisplay failed");
        return false;
    }

    if (eglInitialize(g_egl.display, nullptr, nullptr) != EGL_TRUE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG, "eglInitialize failed: %{public}x", eglGetError());
        return false;
    }

    const EGLint configAttribs[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_DEPTH_SIZE, 24,
        EGL_STENCIL_SIZE, 8,
        EGL_NONE
    };
    EGLint configCount = 0;
    if (eglChooseConfig(g_egl.display, configAttribs, &g_egl.config, 1, &configCount) != EGL_TRUE || configCount < 1) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG, "eglChooseConfig failed: %{public}x", eglGetError());
        return false;
    }

    const EGLint contextAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    g_egl.context = eglCreateContext(g_egl.display, g_egl.config, EGL_NO_CONTEXT, contextAttribs);
    if (g_egl.context == EGL_NO_CONTEXT) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG, "eglCreateContext failed: %{public}x", eglGetError());
        return false;
    }

    g_egl.surface = eglCreateWindowSurface(g_egl.display, g_egl.config, reinterpret_cast<EGLNativeWindowType>(window), nullptr);
    if (g_egl.surface == EGL_NO_SURFACE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG, "eglCreateWindowSurface failed: %{public}x", eglGetError());
        return false;
    }

    if (eglMakeCurrent(g_egl.display, g_egl.surface, g_egl.surface, g_egl.context) != EGL_TRUE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG, "eglMakeCurrent failed: %{public}x", eglGetError());
        return false;
    }

    // Do not make the Qt render thread wait for every display refresh. The
    // compositor still presents at the panel's native refresh rate, while
    // the producer can keep the newest full-resolution frame ready.
    eglSwapInterval(g_egl.display, 0);

    OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG, "EGL initialized");
    return true;
}

bool ensurePreviewResources()
{
    if (g_egl.starProgram == 0) {
        g_egl.starProgram = createStarProgram();
        if (g_egl.starProgram == 0)
            return false;
    }

    if (g_egl.starBuffer == 0) {
        glGenBuffers(1, &g_egl.starBuffer);
        glBindBuffer(GL_ARRAY_BUFFER, g_egl.starBuffer);
        glBufferData(GL_ARRAY_BUFFER, sizeof(STARS), STARS.data(), GL_STATIC_DRAW);
    }

    return true;
}

void renderPreview()
{
    std::lock_guard<std::mutex> lock(g_renderMutex);
    if (g_egl.display == EGL_NO_DISPLAY || g_egl.surface == EGL_NO_SURFACE || g_egl.context == EGL_NO_CONTEXT)
        return;

    eglMakeCurrent(g_egl.display, g_egl.surface, g_egl.surface, g_egl.context);
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_STENCIL_TEST);
    glViewport(0, 0, g_egl.width > 0 ? g_egl.width : 1440, g_egl.height > 0 ? g_egl.height : 893);
    glClearColor(0.f, 0.f, 0.f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);

    if (eglSwapBuffers(g_egl.display, g_egl.surface) != EGL_TRUE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "preview eglSwapBuffers failed: %{public}x", eglGetError());
    }
    eglMakeCurrent(g_egl.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
}

bool shareContextWithQt(EGLDisplay qtDisplay, EGLContext qtContext)
{
    if (g_egl.sharedTextureContext)
        return true;
    if (g_egl.zeroCopyUnavailable || qtDisplay == EGL_NO_DISPLAY || qtContext == EGL_NO_CONTEXT || qtDisplay != g_egl.display)
        return false;

    // The surface context is created before Qt starts its render loop. Recreate
    // it once with Qt's context as the share context so GL textures remain on
    // the GPU and can be sampled by the XComponent compositor.
    eglMakeCurrent(g_egl.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (g_ar.image != nullptr) {
        OH_NativeImage_DetachContext(g_ar.image);
        g_ar.attachPending = true;
        g_ar.hasFrame = false;
    }
    g_egl.arCompositeProgram = 0;
    g_egl.arCameraTexture = 0;
    if (g_egl.context != EGL_NO_CONTEXT)
        eglDestroyContext(g_egl.display, g_egl.context);

    const EGLint contextAttribs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 3,
        EGL_NONE
    };
    g_egl.context = eglCreateContext(g_egl.display, g_egl.config, qtContext, contextAttribs);
    if (g_egl.context == EGL_NO_CONTEXT) {
        // Keep the proven CPU-copy bridge available when an EGL driver refuses
        // cross-context sharing on a specific device.
        g_egl.context = eglCreateContext(g_egl.display, g_egl.config, EGL_NO_CONTEXT, contextAttribs);
        g_egl.zeroCopyUnavailable = true;
        OH_LOG_Print(LOG_APP, LOG_WARN, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "zero-copy EGL sharing unavailable: %{public}x", eglGetError());
        return false;
    }

    g_egl.sharedTextureContext = true;
    OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                 "zero-copy EGL texture sharing enabled");
    return true;
}

bool renderSubmittedTexture(GLuint texture, int frameWidth, int frameHeight,
                            EGLDisplay qtDisplay, EGLContext qtContext)
{
    std::lock_guard<std::mutex> lock(g_renderMutex);
    if (texture == 0 || frameWidth <= 0 || frameHeight <= 0 ||
        g_egl.display == EGL_NO_DISPLAY || g_egl.surface == EGL_NO_SURFACE || g_egl.context == EGL_NO_CONTEXT)
        return false;

    const EGLDisplay previousDisplay = eglGetCurrentDisplay();
    const EGLSurface previousDrawSurface = eglGetCurrentSurface(EGL_DRAW);
    const EGLSurface previousReadSurface = eglGetCurrentSurface(EGL_READ);
    const EGLContext previousContext = eglGetCurrentContext();
    const auto restorePreviousContext = [&]() {
        if (previousDisplay != EGL_NO_DISPLAY && previousContext != EGL_NO_CONTEXT)
            eglMakeCurrent(previousDisplay, previousDrawSurface, previousReadSurface, previousContext);
        else
            eglMakeCurrent(g_egl.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    };

    if (!shareContextWithQt(qtDisplay, qtContext)) {
        restorePreviousContext();
        return false;
    }
    if (eglMakeCurrent(g_egl.display, g_egl.surface, g_egl.surface, g_egl.context) != EGL_TRUE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "zero-copy eglMakeCurrent failed: %{public}x", eglGetError());
        restorePreviousContext();
        return false;
    }
    if (g_egl.frameProgram == 0) {
        g_egl.frameProgram = createFrameProgram();
        if (g_egl.frameProgram == 0) {
            restorePreviousContext();
            return false;
        }
    }

    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_STENCIL_TEST);
    glDisable(GL_BLEND);
    const auto viewport = fitPresentationFrame(frameWidth, frameHeight,
        g_egl.width > 0 ? g_egl.width : frameWidth, g_egl.height > 0 ? g_egl.height : frameHeight);
    glViewport(viewport.left, viewport.bottom, viewport.width, viewport.height);
    glClearColor(0.f, 0.f, 0.f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT);
    g_egl.lastSkyTexture = texture;
    g_egl.lastSkyWidth = frameWidth;
    g_egl.lastSkyHeight = frameHeight;
    g_egl.lastSkyFovDeg = g_renderedFovDeg.load(std::memory_order_acquire);
    drawSkyWithOptionalArCameraLocked(texture, viewport.width, viewport.height);
    if (glGetError() != GL_NO_ERROR || eglSwapBuffers(g_egl.display, g_egl.surface) != EGL_TRUE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "zero-copy presentation failed: %{public}x", eglGetError());
        restorePreviousContext();
        return false;
    }
    g_presentationState.store(nextPresentationState(g_presentationState.load(), frameWidth, frameHeight,
        g_egl.width, g_egl.height));
    restorePreviousContext();
    if (!g_egl.submittedFrame) {
        OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "displayed zero-copy Stellarium texture %{public}dx%{public}d", frameWidth, frameHeight);
        g_egl.submittedFrame = true;
    }
    return true;
}

void renderSubmittedFrame(const unsigned char* rgba, int frameWidth, int frameHeight)
{
    std::lock_guard<std::mutex> lock(g_renderMutex);
    if (!rgba || frameWidth <= 0 || frameHeight <= 0)
        return;
    if (g_egl.display == EGL_NO_DISPLAY || g_egl.surface == EGL_NO_SURFACE || g_egl.context == EGL_NO_CONTEXT)
        return;

    const EGLDisplay previousDisplay = eglGetCurrentDisplay();
    const EGLSurface previousDrawSurface = eglGetCurrentSurface(EGL_DRAW);
    const EGLSurface previousReadSurface = eglGetCurrentSurface(EGL_READ);
    const EGLContext previousContext = eglGetCurrentContext();
    const auto restorePreviousContext = [&]() {
        if (previousDisplay != EGL_NO_DISPLAY && previousContext != EGL_NO_CONTEXT) {
            eglMakeCurrent(previousDisplay, previousDrawSurface, previousReadSurface, previousContext);
        } else {
            eglMakeCurrent(g_egl.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        }
    };

    if (eglMakeCurrent(g_egl.display, g_egl.surface, g_egl.surface, g_egl.context) != EGL_TRUE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "submitFrame eglMakeCurrent failed: %{public}x", eglGetError());
        return;
    }

    if (g_egl.frameProgram == 0) {
        g_egl.frameProgram = createFrameProgram();
        if (g_egl.frameProgram == 0) {
            restorePreviousContext();
            return;
        }
    }

    if (g_egl.frameTexture == 0) {
        glGenTextures(1, &g_egl.frameTexture);
        glBindTexture(GL_TEXTURE_2D, g_egl.frameTexture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    } else {
        glBindTexture(GL_TEXTURE_2D, g_egl.frameTexture);
    }

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    if (g_egl.frameTextureWidth != frameWidth || g_egl.frameTextureHeight != frameHeight) {
        // Allocate only when the rendered surface changes size. Reallocating a
        // texture on every frame creates avoidable driver synchronization.
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, frameWidth, frameHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
        g_egl.frameTextureWidth = frameWidth;
        g_egl.frameTextureHeight = frameHeight;
    }
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, frameWidth, frameHeight, GL_RGBA, GL_UNSIGNED_BYTE, rgba);
    const GLenum textureError = glGetError();
    if (textureError != GL_NO_ERROR) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "upload submitted frame failed: %{public}x", textureError);
        restorePreviousContext();
        return;
    }

    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_DEPTH_TEST);
    glDisable(GL_STENCIL_TEST);
    glDisable(GL_BLEND);
    const auto viewport = fitPresentationFrame(frameWidth, frameHeight,
        g_egl.width > 0 ? g_egl.width : frameWidth, g_egl.height > 0 ? g_egl.height : frameHeight);
    glViewport(viewport.left, viewport.bottom, viewport.width, viewport.height);
    glClearColor(0.f, 0.f, 0.f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT);
    g_egl.lastSkyTexture = g_egl.frameTexture;
    g_egl.lastSkyWidth = frameWidth;
    g_egl.lastSkyHeight = frameHeight;
    g_egl.lastSkyFovDeg = g_renderedFovDeg.load(std::memory_order_acquire);
    drawSkyWithOptionalArCameraLocked(g_egl.frameTexture, viewport.width, viewport.height);
    const GLenum drawError = glGetError();
    if (drawError != GL_NO_ERROR) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "draw submitted frame failed: %{public}x", drawError);
        restorePreviousContext();
        return;
    }

    if (eglSwapBuffers(g_egl.display, g_egl.surface) != EGL_TRUE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "submitted frame eglSwapBuffers failed: %{public}x", eglGetError());
        restorePreviousContext();
        return;
    }
    g_presentationState.store(nextPresentationState(g_presentationState.load(), frameWidth, frameHeight,
        g_egl.width, g_egl.height));
    restorePreviousContext();
    if (!g_egl.submittedFrame) {
        OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "displayed submitted Stellarium frame %{public}dx%{public}d", frameWidth, frameHeight);
        g_egl.submittedFrame = true;
    }
}

void destroyEgl()
{
    std::lock_guard<std::mutex> lock(g_renderMutex);
    if (g_egl.display != EGL_NO_DISPLAY) {
        if (g_egl.surface != EGL_NO_SURFACE && g_egl.context != EGL_NO_CONTEXT) {
            eglMakeCurrent(g_egl.display, g_egl.surface, g_egl.surface, g_egl.context);
        }
        cleanupArCameraGlResourcesLocked();
        if (g_egl.arCompositeProgram != 0)
            glDeleteProgram(g_egl.arCompositeProgram);
        eglMakeCurrent(g_egl.display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
        if (g_egl.starBuffer != 0)
            glDeleteBuffers(1, &g_egl.starBuffer);
        if (g_egl.starProgram != 0)
            glDeleteProgram(g_egl.starProgram);
        if (g_egl.frameTexture != 0)
            glDeleteTextures(1, &g_egl.frameTexture);
        if (g_egl.frameProgram != 0)
            glDeleteProgram(g_egl.frameProgram);
        if (g_egl.surface != EGL_NO_SURFACE)
            eglDestroySurface(g_egl.display, g_egl.surface);
        if (g_egl.context != EGL_NO_CONTEXT)
            eglDestroyContext(g_egl.display, g_egl.context);
        eglTerminate(g_egl.display);
    }
    g_egl = EglState {};
}

void onSurfaceCreated(OH_NativeXComponent* component, void* window)
{
    g_presentationState.store(0);
    uint64_t width = 0;
    uint64_t height = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
    g_egl.width = static_cast<int>(width);
    g_egl.height = static_cast<int>(height);
    OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                 "surface created %{public}dx%{public}d", g_egl.width, g_egl.height);
    if (initEgl(window))
        renderPreview();
}

void onSurfaceChanged(OH_NativeXComponent* component, void* window)
{
    g_presentationState.store(0);
    uint64_t width = 0;
    uint64_t height = 0;
    OH_NativeXComponent_GetXComponentSize(component, window, &width, &height);
    g_egl.width = static_cast<int>(width);
    g_egl.height = static_cast<int>(height);
    OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                 "surface changed %{public}dx%{public}d", g_egl.width, g_egl.height);
    if (!g_egl.submittedFrame)
        renderPreview();
}

void onSurfaceDestroyed(OH_NativeXComponent*, void*)
{
    g_presentationState.store(0);
    OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG, "surface destroyed");
    destroyEgl();
}

void dispatchTouchEvent(OH_NativeXComponent*, void*)
{
    OH_LOG_Print(LOG_APP, LOG_DEBUG, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG, "touch ignored by frame surface");
}

void registerNativeXComponent(napi_env env, napi_value exports)
{
    napi_value nativeXComponentValue = nullptr;
    if (napi_get_named_property(env, exports, OH_NATIVE_XCOMPONENT_OBJ, &nativeXComponentValue) != napi_ok)
        return;

    OH_NativeXComponent* component = nullptr;
    if (napi_unwrap(env, nativeXComponentValue, reinterpret_cast<void**>(&component)) != napi_ok || component == nullptr)
        return;

    g_xcomponentCallback = {
        .OnSurfaceCreated = onSurfaceCreated,
        .OnSurfaceChanged = onSurfaceChanged,
        .OnSurfaceDestroyed = onSurfaceDestroyed,
        .DispatchTouchEvent = dispatchTouchEvent,
    };
    OH_NativeXComponent_RegisterCallback(component, &g_xcomponentCallback);
    OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG, "registered native XComponent callback");
}

}

extern "C" __attribute__((visibility("default"))) void StellariumEntry_submitFrame(const unsigned char* rgba, int width, int height)
{
    static bool loggedSubmit = false;
    if (!loggedSubmit) {
        OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "received first Stellarium frame %{public}dx%{public}d", width, height);
        loggedSubmit = true;
    }
    renderSubmittedFrame(rgba, width, height);
}

extern "C" __attribute__((visibility("default"))) void StellariumEntry_setRenderedFov(double fovDeg)
{
    if (std::isfinite(fovDeg) && fovDeg >= 0.5 && fovDeg <= 179.0) {
        g_renderedFovDeg.store(static_cast<float>(fovDeg), std::memory_order_release);
    }
}

extern "C" __attribute__((visibility("default"))) bool StellariumEntry_submitTexture(
    unsigned int texture, int width, int height, void* qtDisplay, void* qtContext)
{
    const bool accepted = renderSubmittedTexture(texture, width, height,
                                 reinterpret_cast<EGLDisplay>(qtDisplay),
                                 reinterpret_cast<EGLContext>(qtContext));
    static bool loggedTexturePath = false;
    if (!loggedTexturePath) {
        OH_LOG_Print(LOG_APP, accepted ? LOG_INFO : LOG_WARN, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "zero-copy texture submit %{public}s %{public}dx%{public}d qtDisplay=%{public}p qtContext=%{public}p eglError=%{public}x",
                     accepted ? "accepted" : "rejected", width, height, qtDisplay, qtContext, eglGetError());
        loggedTexturePath = true;
    }
    return accepted;
}

static bool getStringArg(napi_env env, napi_value value, std::string &out)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok)
        return false;

    std::vector<char> buffer(length + 1);
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &copied) != napi_ok)
        return false;

    out.assign(buffer.data(), copied);
    return true;
}

static napi_value Add(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    double value0 = 0.0;
    double value1 = 0.0;
    napi_get_value_double(env, args[0], &value0);
    napi_get_value_double(env, args[1], &value1);

    napi_value sum;
    napi_create_double(env, value0 + value1, &sum);
    return sum;
}

static napi_value SetEnv(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string name;
    std::string value;
    const bool ok = argc == 2 && getStringArg(env, args[0], name) && getStringArg(env, args[1], value)
        && setenv(name.c_str(), value.c_str(), 1) == 0;

    napi_value result;
    napi_get_boolean(env, ok, &result);
    return result;
}

StellariumCommandFunc resolveStellariumCommand()
{
    static StellariumCommandFunc command = nullptr;
    static bool resolved = false;
    if (resolved)
        return command;

    // IMPORTANT: never trigger the *initial* load of libstellarium.so from
    // the ArkUI/JS thread. libstellarium.so is the application binary that
    // contains Stellarium's Qt main() entry point; it is loaded and launched
    // by the Qt-for-OHOS plugin (libqohos.so) on the dedicated Qt main
    // thread when the QAbility starts the Qt application. Loading it
    // prematurely here (from the ArkUI UI thread) races Qt's own bootstrap
    // inside makeQtThreadWithMainFuncLauncher and aborts the process with
    // "Qt API was likely used before Qt initialization. Aborting."
    // So we only *look up* an already-loaded library (RTLD_NOLOAD). If it
    // is not loaded yet, return null and let the ArkUI side retry until Qt
    // is up.
    void* handle = dlopen("libstellarium.so", RTLD_NOW | RTLD_NOLOAD);
    if (!handle) {
        OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "Stellarium command bridge not loaded yet (Qt core not started)");
        return nullptr;
    }

    command = reinterpret_cast<StellariumCommandFunc>(dlsym(handle, "StellariumOhos_command"));
    if (command)
        resolved = true;
    OH_LOG_Print(LOG_APP, command ? LOG_INFO : LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                 command ? "Stellarium command bridge resolved" : "Stellarium command bridge not found");
    return command;
}

using StellariumReadyFunc = bool (*)();

static StellariumReadyFunc resolveStellariumReady()
{
    // Same rule as resolveStellariumCommand(): only look at an already loaded
    // engine, never trigger its initial load from the ArkUI thread.
    void* handle = dlopen("libstellarium.so", RTLD_NOW | RTLD_NOLOAD);
    if (!handle)
        return nullptr;
    return reinterpret_cast<StellariumReadyFunc>(dlsym(handle, "StellariumOhos_isInitialized"));
}

static napi_value IsEngineReady(napi_env env, napi_callback_info info)
{
    StellariumReadyFunc ready = resolveStellariumReady();
    napi_value result;
    napi_get_boolean(env, ready != nullptr && ready(), &result);
    return result;
}

static napi_value Command(napi_env env, napi_callback_info info)
{
    size_t argc = 2;
    napi_value args[2] = { nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    std::string commandName;
    std::string payload;
    const bool hasArgs = argc >= 1 && getStringArg(env, args[0], commandName)
        && (argc < 2 || getStringArg(env, args[1], payload));

    std::string response = R"({"ok":false,"error":"invalid arguments"})";
    if (hasArgs && commandName == "getPresentationState") {
        const auto state = g_presentationState.load();
        response = std::string("{\"ok\":true,\"ready\":") + ((state & 0xffff) >= 2 ? "true" : "false") +
            ",\"width\":" + std::to_string(state >> 32) +
            ",\"height\":" + std::to_string((state >> 16) & 0xffff) + "}";
    } else if (hasArgs) {
        StellariumCommandFunc command = resolveStellariumCommand();
        if (command) {
            // Continuous view commands are intentionally silent. Logging each
            // drag sample can contend with the UI thread during a gesture.
            const bool continuous = commandName == "dragView" || commandName == "zoomBy" ||
                                    commandName == "panBy" || commandName == "setGyroView" ||
                                    commandName == "setSpectralLens";
            if (!continuous) {
                OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                             "Stellarium command %{public}s", commandName.c_str());
            }
            const char* nativeResponse = command(commandName.c_str(), payload.c_str());
            response = nativeResponse ? nativeResponse : R"({"ok":false,"error":"empty native response"})";
        } else {
            response = R"({"ok":false,"error":"bridge not available"})";
        }
    }

    napi_value result;
    napi_create_string_utf8(env, response.c_str(), response.size(), &result);
    return result;
}

static napi_value IsPresentationReady(napi_env env, napi_callback_info info)
{
    const auto state = g_presentationState.load();
    napi_value result;
    napi_get_boolean(env, (state & 0xffff) >= 2, &result);
    return result;
}

static napi_value ProbeArHardware(napi_env env, napi_callback_info info)
{
    using CheckSupportedFunc = int32_t (*)(int32_t);
    bool arEngineLib = false;
    bool slam = false;
    bool depth = false;
    bool mesh = false;
    bool semantic = false;

    void* handle = dlopen("libarengine_ndk.z.so", RTLD_LAZY);
    if (handle != nullptr) {
        arEngineLib = true;
        auto checkFn = reinterpret_cast<CheckSupportedFunc>(dlsym(handle, "HMS_AREngine_CheckSupported"));
        if (checkFn != nullptr) {
            slam = (checkFn(0) == 0);      // ARENGINE_FEATURE_TYPE_SLAM
            depth = (checkFn(1) == 0);     // ARENGINE_FEATURE_TYPE_DEPTH
            mesh = (checkFn(2) == 0);      // ARENGINE_FEATURE_TYPE_MESH
            semantic = (checkFn(5) == 0);  // ARENGINE_FEATURE_TYPE_SEMANTIC
        }
        dlclose(handle);
    }

    const std::string json = std::string("{\"nativeImage\":true,\"arEngineLib\":") +
        (arEngineLib ? "true" : "false") +
        ",\"slam\":" + (slam ? "true" : "false") +
        ",\"depth\":" + (depth ? "true" : "false") +
        ",\"mesh\":" + (mesh ? "true" : "false") +
        ",\"semantic\":" + (semantic ? "true" : "false") + "}";
    OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                 "[ar-probe] hardware=%{public}s", json.c_str());

    napi_value result;
    napi_create_string_utf8(env, json.c_str(), json.size(), &result);
    return result;
}

static napi_value CreateArCameraSurface(napi_env env, napi_callback_info info)
{
    std::string surfaceIdStr;
    {
        std::lock_guard<std::mutex> lock(g_renderMutex);
        if (g_ar.image != nullptr) {
            g_ar.destroyPending = false;
            g_ar.hasFrame = false;
            g_arFrameAvailable.store(false, std::memory_order_release);
            if (g_ar.surfaceId != 0) {
                surfaceIdStr = std::to_string(g_ar.surfaceId);
            }
        }
        if (g_ar.image == nullptr) {
            OH_NativeImage* img = OH_NativeImage_Create(0, GL_TEXTURE_EXTERNAL_OES);
            if (img != nullptr) {
                uint64_t sid = 0;
                const int32_t sidRet = OH_NativeImage_GetSurfaceId(img, &sid);
                if (sidRet == 0 && sid != 0) {
                    OH_OnFrameAvailableListener listener { nullptr, onArCameraFrameAvailable };
                    OH_NativeImage_SetOnFrameAvailableListener(img, listener);
                    g_ar.image = img;
                    g_ar.surfaceId = sid;
                    g_ar.attachPending = true;
                    g_ar.destroyPending = false;
                    g_ar.hasFrame = false;
                    g_arFrameAvailable.store(false, std::memory_order_release);
                    surfaceIdStr = std::to_string(sid);
                    ensureArCameraPresentThreadStarted();
                    OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                                 "[ar-camera] created OH_NativeImage surfaceId=%{public}s", surfaceIdStr.c_str());
                } else {
                    OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                                 "[ar-camera] OH_NativeImage_GetSurfaceId failed ret=%{public}d", sidRet);
                    OH_NativeImage_Destroy(&img);
                }
            } else {
                OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                             "[ar-camera] OH_NativeImage_Create failed");
            }
        }
    }
    napi_value result;
    napi_create_string_utf8(env, surfaceIdStr.c_str(), surfaceIdStr.size(), &result);
    return result;
}

static napi_value DestroyArCameraSurface(napi_env env, napi_callback_info info)
{
    {
        std::lock_guard<std::mutex> lock(g_renderMutex);
        g_ar.compositeEnabled = false;
        g_ar.hasFrame = false;
        g_arFrameAvailable.store(false, std::memory_order_release);
        if (g_ar.image != nullptr) {
            g_ar.destroyPending = true;
        }
    }
    OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                 "[ar-camera] scheduled native image teardown");
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

static napi_value SetArCameraComposite(napi_env env, napi_callback_info info)
{
    size_t argc = 4;
    napi_value args[4] = { nullptr, nullptr, nullptr, nullptr };
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);

    bool enabled = false;
    double blend = 0.55;
    double cameraAspect = 16.0 / 9.0;
    double baseFovDeg = 45.0;
    bool hasBaseFov = false;
    if (argc >= 1) napi_get_value_bool(env, args[0], &enabled);
    if (argc >= 2) napi_get_value_double(env, args[1], &blend);
    if (argc >= 3) napi_get_value_double(env, args[2], &cameraAspect);
    if (argc >= 4) {
        napi_valuetype t = napi_undefined;
        if (napi_typeof(env, args[3], &t) == napi_ok && t == napi_number) {
            napi_get_value_double(env, args[3], &baseFovDeg);
            hasBaseFov = true;
        }
    }

    {
        std::lock_guard<std::mutex> lock(g_renderMutex);
        g_ar.compositeEnabled = enabled;
        if (std::isfinite(blend)) {
            g_ar.skyBlend = static_cast<float>(std::max(0.0, std::min(1.0, blend)));
        }
        if (std::isfinite(cameraAspect) && cameraAspect > 0.1 && cameraAspect < 10.0) {
            g_ar.cameraAspect = static_cast<float>(cameraAspect);
        }
        if (hasBaseFov && std::isfinite(baseFovDeg) && baseFovDeg >= 15.0 && baseFovDeg <= 100.0) {
            g_ar.baseFovDeg = static_cast<float>(baseFovDeg);
        }
    }
    napi_value undef;
    napi_get_undefined(env, &undef);
    return undef;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setEnv", nullptr, SetEnv, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "command", nullptr, Command, nullptr, nullptr, nullptr, napi_default, nullptr },
        // 纯原子量读取，不经过 Qt 线程：ArkTS 用它判断引擎是否已开始出帧，
        // 未就绪前不向 Qt 队列投放任何命令（启动期同步桥调用会拖死 UI 线程）。
        { "isPresentationReady", nullptr, IsPresentationReady, nullptr, nullptr, nullptr, napi_default, nullptr },
        // StelApp::isInitialized()：引擎真正初始化完成（早于出帧），
        // 启动查询必须等它，否则重试链在 init 期间堆积触发 appfreeze。
        { "isEngineReady", nullptr, IsEngineReady, nullptr, nullptr, nullptr, napi_default, nullptr },
        // AR 实景相机 GPU 融合与硬件能力探测（OH_NativeImage + GL_TEXTURE_EXTERNAL_OES）。
        { "probeArHardware", nullptr, ProbeArHardware, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "createArCameraSurface", nullptr, CreateArCameraSurface, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "destroyArCameraSurface", nullptr, DestroyArCameraSurface, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setArCameraComposite", nullptr, SetArCameraComposite, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    registerDetailModelNapi(env, exports);
    registerNativeXComponent(env, exports);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = ((void*)0),
    .reserved = { 0 },
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&demoModule);
}
