/*
 * Channel headless Qualcomm EGL/GLES2 probe.
 *
 * Built as a preload DSO and injected into the already-initialized recovery
 * /system/bin/sh.  The constructor deliberately exits the host process with
 * the probe status, so "rctools gpu probe" receives an exact pass/fail code.
 *
 * No SurfaceFlinger, HWC, framebuffer or physical panel is required: this
 * creates a 16x16 EGL pbuffer and validates a GPU clear via glReadPixels().
 */

typedef void *EGLDisplay;
typedef void *EGLConfig;
typedef void *EGLSurface;
typedef void *EGLContext;
typedef int EGLint;
typedef unsigned int EGLBoolean;

typedef unsigned int GLenum;
typedef unsigned int GLbitfield;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLubyte;
typedef float GLfloat;

extern EGLDisplay eglGetDisplay(void *display_id);
extern EGLBoolean eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor);
extern EGLint eglGetError(void);
extern const char *eglQueryString(EGLDisplay dpy, EGLint name);
extern EGLBoolean eglBindAPI(unsigned int api);
extern EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *attrs,
                                  EGLConfig *configs, EGLint config_size,
                                  EGLint *num_config);
extern EGLSurface eglCreatePbufferSurface(EGLDisplay dpy, EGLConfig config,
                                          const EGLint *attrs);
extern EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig config,
                                   EGLContext share, const EGLint *attrs);
extern EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw,
                                 EGLSurface read, EGLContext ctx);
extern EGLBoolean eglDestroyContext(EGLDisplay dpy, EGLContext ctx);
extern EGLBoolean eglDestroySurface(EGLDisplay dpy, EGLSurface surface);
extern EGLBoolean eglTerminate(EGLDisplay dpy);

extern const GLubyte *glGetString(GLenum name);
extern void glClearColor(GLfloat r, GLfloat g, GLfloat b, GLfloat a);
extern void glClear(GLbitfield mask);
extern void glFinish(void);
extern void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height,
                         GLenum format, GLenum type, void *pixels);
extern GLenum glGetError(void);

#define SYS_WRITE       64
#define SYS_EXIT_GROUP  94

#define EGL_FALSE               0
#define EGL_TRUE                1
#define EGL_NONE           0x3038
#define EGL_RED_SIZE       0x3024
#define EGL_GREEN_SIZE     0x3023
#define EGL_BLUE_SIZE      0x3022
#define EGL_ALPHA_SIZE     0x3021
#define EGL_SURFACE_TYPE   0x3033
#define EGL_RENDERABLE_TYPE 0x3040
#define EGL_PBUFFER_BIT    0x0001
#define EGL_OPENGL_ES2_BIT 0x0004
#define EGL_WIDTH          0x3057
#define EGL_HEIGHT         0x3056
#define EGL_CONTEXT_CLIENT_VERSION 0x3098
#define EGL_OPENGL_ES_API  0x30A0
#define EGL_VENDOR         0x3053
#define EGL_VERSION        0x3054
#define EGL_EXTENSIONS     0x3055

#define GL_VENDOR          0x1F00
#define GL_RENDERER        0x1F01
#define GL_VERSION         0x1F02
#define GL_COLOR_BUFFER_BIT 0x00004000
#define GL_RGBA            0x1908
#define GL_UNSIGNED_BYTE   0x1401
#define GL_NO_ERROR        0

static long syscall3_probe(long nr, long a0, long a1, long a2)
{
    register long x0 __asm__("x0") = a0;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    register long x8 __asm__("x8") = nr;

    __asm__ volatile(
        "svc 0"
        : "+r"(x0)
        : "r"(x1), "r"(x2), "r"(x8)
        : "memory");

    return x0;
}

static void raw_exit(int code)
{
    (void)syscall3_probe(SYS_EXIT_GROUP, code, 0, 0);
    for (;;) {}
}

static unsigned long slen(const char *s)
{
    unsigned long n = 0;
    if (!s)
        return 0;
    while (s[n])
        ++n;
    return n;
}

static void out_raw(const char *s)
{
    if (s)
        (void)syscall3_probe(SYS_WRITE, 1, (long)s, (long)slen(s));
}

static void out_line(const char *s)
{
    out_raw(s);
    out_raw("\n");
}

static void out_uint(unsigned int v)
{
    char buf[16];
    int i = 15;

    buf[i--] = 0;
    if (v == 0) {
        out_raw("0");
        return;
    }

    while (v && i >= 0) {
        buf[i--] = (char)('0' + (v % 10));
        v /= 10;
    }

    out_raw(&buf[i + 1]);
}

static void out_hex(unsigned int v)
{
    static const char h[] = "0123456789abcdef";
    char buf[11];
    int i;

    buf[0] = '0';
    buf[1] = 'x';
    for (i = 0; i < 8; ++i) {
        unsigned int shift = (unsigned int)(28 - i * 4);
        buf[2 + i] = h[(v >> shift) & 0xf];
    }
    buf[10] = 0;
    out_raw(buf);
}

static void print_string(const char *key, const char *value)
{
    out_raw(key);
    out_raw("=");
    out_line(value ? value : "(null)");
}

static void fail_egl(const char *stage, int rc)
{
    out_raw("FAIL stage=");
    out_line(stage);
    out_raw("EGL_ERROR=");
    out_hex((unsigned int)eglGetError());
    out_raw("\n");
    raw_exit(rc);
}

__attribute__((constructor))
static void run_probe(void)
{
    EGLDisplay display;
    EGLConfig config = (EGLConfig)0;
    EGLSurface surface;
    EGLContext context;
    EGLint major = 0;
    EGLint minor = 0;
    EGLint count = 0;
    GLenum glerr;
    unsigned char pixel[4];
    const EGLint config_rgba[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    const EGLint config_rgb[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_NONE
    };
    const EGLint pbuffer_attrs[] = {
        EGL_WIDTH, 16,
        EGL_HEIGHT, 16,
        EGL_NONE
    };
    const EGLint context_attrs[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE
    };

    pixel[0] = pixel[1] = pixel[2] = pixel[3] = 0;

    out_line("CHANNEL_GPU_EGL_PROBE v1");

    out_line("stage=eglGetDisplay");
    display = eglGetDisplay((void *)0);
    if (!display)
        fail_egl("eglGetDisplay", 10);

    out_line("stage=eglInitialize");
    if (eglInitialize(display, &major, &minor) != EGL_TRUE)
        fail_egl("eglInitialize", 11);

    out_raw("EGL_VERSION_NUM=");
    out_uint((unsigned int)major);
    out_raw(".");
    out_uint((unsigned int)minor);
    out_raw("\n");
    print_string("EGL_VENDOR", eglQueryString(display, EGL_VENDOR));
    print_string("EGL_VERSION", eglQueryString(display, EGL_VERSION));
    print_string("EGL_EXTENSIONS", eglQueryString(display, EGL_EXTENSIONS));

    out_line("stage=eglBindAPI");
    if (eglBindAPI(EGL_OPENGL_ES_API) != EGL_TRUE)
        fail_egl("eglBindAPI", 12);

    out_line("stage=eglChooseConfig");
    if (eglChooseConfig(display, config_rgba, &config, 1, &count) != EGL_TRUE ||
        count < 1) {
        count = 0;
        config = (EGLConfig)0;
        if (eglChooseConfig(display, config_rgb, &config, 1, &count) != EGL_TRUE ||
            count < 1)
            fail_egl("eglChooseConfig", 13);
    }

    out_line("stage=eglCreatePbufferSurface");
    surface = eglCreatePbufferSurface(display, config, pbuffer_attrs);
    if (!surface)
        fail_egl("eglCreatePbufferSurface", 14);

    out_line("stage=eglCreateContext");
    context = eglCreateContext(display, config, (EGLContext)0, context_attrs);
    if (!context)
        fail_egl("eglCreateContext", 15);

    out_line("stage=eglMakeCurrent");
    if (eglMakeCurrent(display, surface, surface, context) != EGL_TRUE)
        fail_egl("eglMakeCurrent", 16);

    print_string("GL_VENDOR", (const char *)glGetString(GL_VENDOR));
    print_string("GL_RENDERER", (const char *)glGetString(GL_RENDERER));
    print_string("GL_VERSION", (const char *)glGetString(GL_VERSION));

    out_line("stage=render");
    glClearColor(1.0f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);
    glFinish();
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    glFinish();

    glerr = glGetError();
    out_raw("GL_ERROR=");
    out_hex(glerr);
    out_raw("\n");

    out_raw("PIXEL_RGBA=");
    out_uint(pixel[0]);
    out_raw(",");
    out_uint(pixel[1]);
    out_raw(",");
    out_uint(pixel[2]);
    out_raw(",");
    out_uint(pixel[3]);
    out_raw("\n");

    (void)eglMakeCurrent(display, (EGLSurface)0, (EGLSurface)0, (EGLContext)0);
    (void)eglDestroyContext(display, context);
    (void)eglDestroySurface(display, surface);
    (void)eglTerminate(display);

    if (glerr != GL_NO_ERROR) {
        out_line("FAIL GPU_GL_ERROR");
        raw_exit(20);
    }

    if (pixel[0] < 200 || pixel[1] > 32 || pixel[2] > 32) {
        out_line("FAIL GPU_PIXEL_MISMATCH");
        raw_exit(21);
    }

    out_line("PASS GPU_RENDER_OK");
    raw_exit(0);
}
