#include <stdio.h>
#include <stdint.h>
#include <string.h>

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>

#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#endif

static void fail(const char *msg)
{
    fprintf(stderr, "%s: EGL=0x%x GL=0x%x\n",
            msg, eglGetError(), glGetError());
}

int main(void)
{
    EGLDisplay dpy;
    EGLint major = 0, minor = 0;

    dpy = eglGetPlatformDisplay(
        EGL_PLATFORM_SURFACELESS_MESA,
        EGL_DEFAULT_DISPLAY,
        NULL
    );

    if (dpy == EGL_NO_DISPLAY) {
        fail("eglGetPlatformDisplay");
        return 1;
    }

    if (!eglInitialize(dpy, &major, &minor)) {
        fail("eglInitialize");
        return 2;
    }

    printf("EGL=%d.%d\n", major, minor);

    if (!eglBindAPI(EGL_OPENGL_ES_API)) {
        fail("eglBindAPI");
        return 3;
    }

    const EGLint cfg_attrs[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE,   8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE,  8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };

    EGLConfig cfg;
    EGLint ncfg = 0;

    if (!eglChooseConfig(dpy, cfg_attrs, &cfg, 1, &ncfg) || ncfg < 1) {
        fail("eglChooseConfig");
        return 4;
    }

    const EGLint surf_attrs[] = {
        EGL_WIDTH, 16,
        EGL_HEIGHT, 16,
        EGL_NONE
    };

    EGLSurface surf = eglCreatePbufferSurface(dpy, cfg, surf_attrs);
    if (surf == EGL_NO_SURFACE) {
        fail("eglCreatePbufferSurface");
        return 5;
    }

    const EGLint ctx_attrs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };

    EGLContext ctx =
        eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, ctx_attrs);

    if (ctx == EGL_NO_CONTEXT) {
        fail("eglCreateContext");
        return 6;
    }

    if (!eglMakeCurrent(dpy, surf, surf, ctx)) {
        fail("eglMakeCurrent");
        return 7;
    }

    const char *vendor = (const char *)glGetString(GL_VENDOR);
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    const char *version = (const char *)glGetString(GL_VERSION);

    printf("GL_VENDOR=%s\n", vendor ? vendor : "(null)");
    printf("GL_RENDERER=%s\n", renderer ? renderer : "(null)");
    printf("GL_VERSION=%s\n", version ? version : "(null)");

    if (!vendor || strcmp(vendor, "freedreno") != 0 ||
        !renderer || strcmp(renderer, "FD506") != 0) {
        fprintf(stderr, "NOT_DIRECT_KGSL_RENDERER\n");
        return 10;
    }

    glViewport(0, 0, 16, 16);
    glClearColor(0.25f, 0.50f, 0.75f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glFinish();

    uint8_t px[4] = {0, 0, 0, 0};

    glReadPixels(8, 8, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);

    GLenum err = glGetError();

    printf("PIXEL=%u,%u,%u,%u\n", px[0], px[1], px[2], px[3]);
    printf("GL_ERROR=0x%x\n", err);

    eglMakeCurrent(dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(dpy, ctx);
    eglDestroySurface(dpy, surf);
    eglTerminate(dpy);

    if (err != GL_NO_ERROR)
        return 8;

    if (px[0] < 60 || px[0] > 68 ||
        px[1] < 124 || px[1] > 132 ||
        px[2] < 187 || px[2] > 195 ||
        px[3] != 255) {
        fprintf(stderr, "PIXEL_MISMATCH\n");
        return 9;
    }

    puts("DIRECT_KGSL_RENDER_OK");
    return 0;
}
