// Copyright (C) 2026 The Qt Company Ltd.
// SPDX-License-Identifier: LicenseRef-Qt-Commercial OR LGPL-3.0-only OR GPL-2.0-only OR GPL-3.0-only

#include "napi/native_api.h"

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <ace/xcomponent/native_interface_xcomponent.h>
#include <hilog/log.h>

#include <array>
#include <cstddef>
#include <cstdlib>
#include <dlfcn.h>
#include <mutex>
#include <string>
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
    int frameTextureWidth = 0;
    int frameTextureHeight = 0;
    bool submittedFrame = false;
    bool sharedTextureContext = false;
    bool zeroCopyUnavailable = false;
};

EglState g_egl;
OH_NativeXComponent_Callback g_xcomponentCallback;
std::mutex g_renderMutex;

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
    glViewport(0, 0, g_egl.width > 0 ? g_egl.width : frameWidth, g_egl.height > 0 ? g_egl.height : frameHeight);
    glClearColor(0.f, 0.f, 0.f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT);
    glUseProgram(g_egl.frameProgram);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture);
    glUniform1i(glGetUniformLocation(g_egl.frameProgram, "u_frame"), 0);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    if (glGetError() != GL_NO_ERROR || eglSwapBuffers(g_egl.display, g_egl.surface) != EGL_TRUE) {
        OH_LOG_Print(LOG_APP, LOG_ERROR, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "zero-copy presentation failed: %{public}x", eglGetError());
        restorePreviousContext();
        return false;
    }
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
    glViewport(0, 0, g_egl.width > 0 ? g_egl.width : frameWidth, g_egl.height > 0 ? g_egl.height : frameHeight);
    glClearColor(0.f, 0.f, 0.f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT);
    glUseProgram(g_egl.frameProgram);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, g_egl.frameTexture);
    glUniform1i(glGetUniformLocation(g_egl.frameProgram, "u_frame"), 0);
    glDrawArrays(GL_TRIANGLES, 0, 3);
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
    restorePreviousContext();
    if (!g_egl.submittedFrame) {
        OH_LOG_Print(LOG_APP, LOG_INFO, STEL_ENTRY_LOG_DOMAIN, STEL_ENTRY_LOG_TAG,
                     "displayed submitted Stellarium frame %{public}dx%{public}d", frameWidth, frameHeight);
        g_egl.submittedFrame = true;
    }
}

void destroyEgl()
{
    if (g_egl.display != EGL_NO_DISPLAY) {
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
    if (hasArgs) {
        StellariumCommandFunc command = resolveStellariumCommand();
        if (command) {
            // Continuous view commands are intentionally silent. Logging each
            // drag sample can contend with the UI thread during a gesture.
            const bool continuous = commandName == "dragView" || commandName == "zoomBy" ||
                                    commandName == "panBy" || commandName == "setGyroView";
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

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        { "add", nullptr, Add, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "setEnv", nullptr, SetEnv, nullptr, nullptr, nullptr, napi_default, nullptr },
        { "command", nullptr, Command, nullptr, nullptr, nullptr, napi_default, nullptr },
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
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
