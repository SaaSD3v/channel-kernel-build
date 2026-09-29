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


#ifdef BUILD_OPENCL_STUB
typedef int cl_int;
typedef unsigned int cl_uint;
typedef unsigned long cl_ulong;
typedef cl_ulong cl_bitfield;
typedef cl_bitfield cl_device_type;
typedef cl_bitfield cl_mem_flags;
typedef unsigned int cl_bool;
typedef long cl_context_properties;
typedef unsigned long size_t_cl;
typedef void *cl_platform_id;
typedef void *cl_device_id;
typedef void *cl_context;
typedef void *cl_command_queue;
typedef void *cl_mem;
typedef void *cl_program;
typedef void *cl_kernel;
typedef void *cl_event;

cl_int clGetPlatformIDs(cl_uint a, cl_platform_id *b, cl_uint *c)
{ (void)a; (void)b; (void)c; return -1; }
cl_int clGetPlatformInfo(cl_platform_id a, cl_uint b, size_t_cl c, void *d, size_t_cl *e)
{ (void)a; (void)b; (void)c; (void)d; (void)e; return -1; }
cl_int clGetDeviceIDs(cl_platform_id a, cl_device_type b, cl_uint c, cl_device_id *d, cl_uint *e)
{ (void)a; (void)b; (void)c; (void)d; (void)e; return -1; }
cl_int clGetDeviceInfo(cl_device_id a, cl_uint b, size_t_cl c, void *d, size_t_cl *e)
{ (void)a; (void)b; (void)c; (void)d; (void)e; return -1; }
cl_context clCreateContext(const cl_context_properties *a, cl_uint b, const cl_device_id *c, void *d, void *e, cl_int *f)
{ (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; return (cl_context)0; }
cl_command_queue clCreateCommandQueue(cl_context a, cl_device_id b, cl_bitfield c, cl_int *d)
{ (void)a; (void)b; (void)c; (void)d; return (cl_command_queue)0; }
cl_mem clCreateBuffer(cl_context a, cl_mem_flags b, size_t_cl c, void *d, cl_int *e)
{ (void)a; (void)b; (void)c; (void)d; (void)e; return (cl_mem)0; }
cl_program clCreateProgramWithSource(cl_context a, cl_uint b, const char **c, const size_t_cl *d, cl_int *e)
{ (void)a; (void)b; (void)c; (void)d; (void)e; return (cl_program)0; }
cl_int clBuildProgram(cl_program a, cl_uint b, const cl_device_id *c, const char *d, void *e, void *f)
{ (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; return -1; }
cl_int clGetProgramBuildInfo(cl_program a, cl_device_id b, cl_uint c, size_t_cl d, void *e, size_t_cl *f)
{ (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; return -1; }
cl_kernel clCreateKernel(cl_program a, const char *b, cl_int *c)
{ (void)a; (void)b; (void)c; return (cl_kernel)0; }
cl_int clSetKernelArg(cl_kernel a, cl_uint b, size_t_cl c, const void *d)
{ (void)a; (void)b; (void)c; (void)d; return -1; }
cl_int clEnqueueWriteBuffer(cl_command_queue a, cl_mem b, cl_bool c, size_t_cl d, size_t_cl e, const void *f, cl_uint g, const cl_event *h, cl_event *i)
{ (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g; (void)h; (void)i; return -1; }
cl_int clEnqueueNDRangeKernel(cl_command_queue a, cl_kernel b, cl_uint c, const size_t_cl *d, const size_t_cl *e, const size_t_cl *f, cl_uint g, const cl_event *h, cl_event *i)
{ (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g; (void)h; (void)i; return -1; }
cl_int clFinish(cl_command_queue a) { (void)a; return -1; }
cl_int clEnqueueReadBuffer(cl_command_queue a, cl_mem b, cl_bool c, size_t_cl d, size_t_cl e, void *f, cl_uint g, const cl_event *h, cl_event *i)
{ (void)a; (void)b; (void)c; (void)d; (void)e; (void)f; (void)g; (void)h; (void)i; return -1; }
cl_int clReleaseKernel(cl_kernel a) { (void)a; return 0; }
cl_int clReleaseProgram(cl_program a) { (void)a; return 0; }
cl_int clReleaseMemObject(cl_mem a) { (void)a; return 0; }
cl_int clReleaseCommandQueue(cl_command_queue a) { (void)a; return 0; }
cl_int clReleaseContext(cl_context a) { (void)a; return 0; }
#endif

#ifdef BUILD_HARDWARE_STUB
struct hw_module_t;
int hw_get_module(const char *id, const struct hw_module_t **module)
{ (void)id; (void)module; return -1; }
#endif
