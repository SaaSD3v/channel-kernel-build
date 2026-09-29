/*
 * Build-time import stubs only.
 *
 * These tiny DSOs are never staged into recovery.  They give GNU ld the
 * symbol/SONAME information needed to make rctools-gpu-probe.so depend on
 * Qualcomm's real libEGL_adreno.so and libGLESv2_adreno.so at runtime.
 */

#ifdef BUILD_EGL_STUB
typedef void *EGLDisplay;
typedef void *EGLConfig;
typedef void *EGLSurface;
typedef void *EGLContext;
typedef int EGLint;
typedef unsigned int EGLBoolean;

EGLDisplay eglGetDisplay(void *display_id) { return display_id; }
EGLBoolean eglInitialize(EGLDisplay dpy, EGLint *major, EGLint *minor)
{ (void)dpy; (void)major; (void)minor; return 0; }
EGLint eglGetError(void) { return 0; }
const char *eglQueryString(EGLDisplay dpy, EGLint name)
{ (void)dpy; (void)name; return (const char *)0; }
EGLBoolean eglBindAPI(unsigned int api) { (void)api; return 0; }
EGLBoolean eglChooseConfig(EGLDisplay dpy, const EGLint *attrs,
                           EGLConfig *configs, EGLint size, EGLint *count)
{ (void)dpy; (void)attrs; (void)configs; (void)size; (void)count; return 0; }
EGLSurface eglCreatePbufferSurface(EGLDisplay dpy, EGLConfig config,
                                   const EGLint *attrs)
{ (void)dpy; (void)config; (void)attrs; return (EGLSurface)0; }
EGLContext eglCreateContext(EGLDisplay dpy, EGLConfig config,
                            EGLContext share, const EGLint *attrs)
{ (void)dpy; (void)config; (void)share; (void)attrs; return (EGLContext)0; }
EGLBoolean eglMakeCurrent(EGLDisplay dpy, EGLSurface draw,
                          EGLSurface read, EGLContext ctx)
{ (void)dpy; (void)draw; (void)read; (void)ctx; return 0; }
EGLBoolean eglDestroyContext(EGLDisplay dpy, EGLContext ctx)
{ (void)dpy; (void)ctx; return 0; }
EGLBoolean eglDestroySurface(EGLDisplay dpy, EGLSurface surface)
{ (void)dpy; (void)surface; return 0; }
EGLBoolean eglTerminate(EGLDisplay dpy) { (void)dpy; return 0; }
#endif

#ifdef BUILD_GLES_STUB
typedef unsigned int GLenum;
typedef unsigned int GLbitfield;
typedef int GLint;
typedef int GLsizei;
typedef unsigned char GLubyte;
typedef float GLfloat;

const GLubyte *glGetString(GLenum name) { (void)name; return (const GLubyte *)0; }
void glClearColor(GLfloat r, GLfloat g, GLfloat b, GLfloat a)
{ (void)r; (void)g; (void)b; (void)a; }
void glClear(GLbitfield mask) { (void)mask; }
void glFinish(void) {}
void glReadPixels(GLint x, GLint y, GLsizei width, GLsizei height,
                  GLenum format, GLenum type, void *pixels)
{ (void)x; (void)y; (void)width; (void)height; (void)format; (void)type; (void)pixels; }
GLenum glGetError(void) { return 0; }
#endif
