/*
 * Channel Qualcomm OpenCL execution probe.
 *
 * Loaded as a constructor DSO into recovery /system/bin/sh.  It exercises
 * platform/device discovery, context/queue creation, runtime compilation,
 * a real GPU vector-add kernel, and readback.  Success therefore proves more
 * than linker availability: commands were accepted and completed by the
 * OpenCL device exposed by the Adreno userspace stack.
 */

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

extern cl_int clGetPlatformIDs(cl_uint, cl_platform_id *, cl_uint *);
extern cl_int clGetPlatformInfo(cl_platform_id, cl_uint, size_t_cl, void *, size_t_cl *);
extern cl_int clGetDeviceIDs(cl_platform_id, cl_device_type, cl_uint, cl_device_id *, cl_uint *);
extern cl_int clGetDeviceInfo(cl_device_id, cl_uint, size_t_cl, void *, size_t_cl *);
extern cl_context clCreateContext(const cl_context_properties *, cl_uint,
                                  const cl_device_id *, void *, void *, cl_int *);
extern cl_command_queue clCreateCommandQueue(cl_context, cl_device_id,
                                             cl_bitfield, cl_int *);
extern cl_mem clCreateBuffer(cl_context, cl_mem_flags, size_t_cl, void *, cl_int *);
extern cl_program clCreateProgramWithSource(cl_context, cl_uint,
                                            const char **, const size_t_cl *, cl_int *);
extern cl_int clBuildProgram(cl_program, cl_uint, const cl_device_id *,
                             const char *, void *, void *);
extern cl_int clGetProgramBuildInfo(cl_program, cl_device_id, cl_uint,
                                    size_t_cl, void *, size_t_cl *);
extern cl_kernel clCreateKernel(cl_program, const char *, cl_int *);
extern cl_int clSetKernelArg(cl_kernel, cl_uint, size_t_cl, const void *);
extern cl_int clEnqueueWriteBuffer(cl_command_queue, cl_mem, cl_bool,
                                   size_t_cl, size_t_cl, const void *,
                                   cl_uint, const cl_event *, cl_event *);
extern cl_int clEnqueueNDRangeKernel(cl_command_queue, cl_kernel, cl_uint,
                                     const size_t_cl *, const size_t_cl *,
                                     const size_t_cl *, cl_uint,
                                     const cl_event *, cl_event *);
extern cl_int clFinish(cl_command_queue);
extern cl_int clEnqueueReadBuffer(cl_command_queue, cl_mem, cl_bool,
                                  size_t_cl, size_t_cl, void *,
                                  cl_uint, const cl_event *, cl_event *);
extern cl_int clReleaseKernel(cl_kernel);
extern cl_int clReleaseProgram(cl_program);
extern cl_int clReleaseMemObject(cl_mem);
extern cl_int clReleaseCommandQueue(cl_command_queue);
extern cl_int clReleaseContext(cl_context);

#define SYS_WRITE       64
#define SYS_EXIT_GROUP  94

#define CL_SUCCESS                  0
#define CL_TRUE                     1
#define CL_DEVICE_TYPE_GPU          (1UL << 2)
#define CL_MEM_READ_WRITE           (1UL << 0)
#define CL_PLATFORM_VERSION         0x0901
#define CL_PLATFORM_NAME            0x0902
#define CL_PLATFORM_VENDOR          0x0903
#define CL_DEVICE_NAME              0x102B
#define CL_DEVICE_VENDOR            0x102C
#define CL_DRIVER_VERSION           0x102D
#define CL_DEVICE_VERSION           0x102F
#define CL_PROGRAM_BUILD_LOG        0x1183

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

static void out_int(int v)
{
    char buf[24];
    unsigned int n;
    int i = 23;

    buf[i--] = 0;
    if (v < 0) {
        n = (unsigned int)(-v);
    } else {
        n = (unsigned int)v;
    }

    if (n == 0) {
        out_raw("0");
        return;
    }

    while (n && i >= 1) {
        buf[i--] = (char)('0' + (n % 10));
        n /= 10;
    }

    if (v < 0)
        buf[i--] = '-';

    out_raw(&buf[i + 1]);
}

static void print_string_info_platform(cl_platform_id p, cl_uint key,
                                       const char *label)
{
    char buf[256];
    size_t_cl got = 0;
    cl_int rc;

    buf[0] = 0;
    rc = clGetPlatformInfo(p, key, sizeof(buf) - 1, buf, &got);
    out_raw(label);
    out_raw("=");
    if (rc == CL_SUCCESS) {
        buf[sizeof(buf) - 1] = 0;
        out_line(buf);
    } else {
        out_raw("ERROR:");
        out_int(rc);
        out_raw("\n");
    }
}

static void print_string_info_device(cl_device_id d, cl_uint key,
                                     const char *label)
{
    char buf[256];
    size_t_cl got = 0;
    cl_int rc;

    buf[0] = 0;
    rc = clGetDeviceInfo(d, key, sizeof(buf) - 1, buf, &got);
    out_raw(label);
    out_raw("=");
    if (rc == CL_SUCCESS) {
        buf[sizeof(buf) - 1] = 0;
        out_line(buf);
    } else {
        out_raw("ERROR:");
        out_int(rc);
        out_raw("\n");
    }
}

static void fail_rc(const char *stage, cl_int rc, int exit_code)
{
    out_raw("FAIL stage=");
    out_raw(stage);
    out_raw(" CL_ERROR=");
    out_int(rc);
    out_raw("\n");
    raw_exit(exit_code);
}

__attribute__((constructor))
static void run_opencl_probe(void)
{
    cl_platform_id platform = (cl_platform_id)0;
    cl_device_id device = (cl_device_id)0;
    cl_context context = (cl_context)0;
    cl_command_queue queue = (cl_command_queue)0;
    cl_mem ba = (cl_mem)0, bb = (cl_mem)0, bc = (cl_mem)0;
    cl_program program = (cl_program)0;
    cl_kernel kernel = (cl_kernel)0;
    cl_uint np = 0, nd = 0;
    cl_int rc = 0;
    cl_int err = 0;
    int a[4] = {1, 2, 3, 4};
    int b[4] = {10, 20, 30, 40};
    int c[4] = {0, 0, 0, 0};
    size_t_cl global = 4;
    static const char source[] =
        "__kernel void add(__global const int *a, __global const int *b, "
        "__global int *c) { size_t i=get_global_id(0); c[i]=a[i]+b[i]; }";
    const char *srcp = source;
    size_t_cl srclen = sizeof(source) - 1;

    out_line("CHANNEL_GPU_OPENCL_PROBE v1");

    out_line("stage=clGetPlatformIDs");
    rc = clGetPlatformIDs(1, &platform, &np);
    if (rc != CL_SUCCESS || np < 1 || !platform)
        fail_rc("clGetPlatformIDs", rc, 30);

    print_string_info_platform(platform, CL_PLATFORM_NAME, "CL_PLATFORM_NAME");
    print_string_info_platform(platform, CL_PLATFORM_VENDOR, "CL_PLATFORM_VENDOR");
    print_string_info_platform(platform, CL_PLATFORM_VERSION, "CL_PLATFORM_VERSION");

    out_line("stage=clGetDeviceIDs");
    rc = clGetDeviceIDs(platform, CL_DEVICE_TYPE_GPU, 1, &device, &nd);
    if (rc != CL_SUCCESS || nd < 1 || !device)
        fail_rc("clGetDeviceIDs", rc, 31);

    print_string_info_device(device, CL_DEVICE_NAME, "CL_DEVICE_NAME");
    print_string_info_device(device, CL_DEVICE_VENDOR, "CL_DEVICE_VENDOR");
    print_string_info_device(device, CL_DEVICE_VERSION, "CL_DEVICE_VERSION");
    print_string_info_device(device, CL_DRIVER_VERSION, "CL_DRIVER_VERSION");

    out_line("stage=clCreateContext");
    context = clCreateContext((const cl_context_properties *)0, 1,
                              &device, (void *)0, (void *)0, &err);
    if (!context || err != CL_SUCCESS)
        fail_rc("clCreateContext", err, 32);

    out_line("stage=clCreateCommandQueue");
    queue = clCreateCommandQueue(context, device, 0, &err);
    if (!queue || err != CL_SUCCESS)
        fail_rc("clCreateCommandQueue", err, 33);

    out_line("stage=clCreateBuffer");
    ba = clCreateBuffer(context, CL_MEM_READ_WRITE, sizeof(a), (void *)0, &err);
    if (!ba || err != CL_SUCCESS)
        fail_rc("clCreateBuffer(a)", err, 34);
    bb = clCreateBuffer(context, CL_MEM_READ_WRITE, sizeof(b), (void *)0, &err);
    if (!bb || err != CL_SUCCESS)
        fail_rc("clCreateBuffer(b)", err, 35);
    bc = clCreateBuffer(context, CL_MEM_READ_WRITE, sizeof(c), (void *)0, &err);
    if (!bc || err != CL_SUCCESS)
        fail_rc("clCreateBuffer(c)", err, 36);

    out_line("stage=clCreateProgramWithSource");
    program = clCreateProgramWithSource(context, 1, &srcp, &srclen, &err);
    if (!program || err != CL_SUCCESS)
        fail_rc("clCreateProgramWithSource", err, 37);

    out_line("stage=clBuildProgram");
    rc = clBuildProgram(program, 1, &device, (const char *)0,
                        (void *)0, (void *)0);
    if (rc != CL_SUCCESS) {
        char logbuf[2048];
        size_t_cl got = 0;
        logbuf[0] = 0;
        (void)clGetProgramBuildInfo(program, device, CL_PROGRAM_BUILD_LOG,
                                    sizeof(logbuf) - 1, logbuf, &got);
        logbuf[sizeof(logbuf) - 1] = 0;
        out_raw("CL_BUILD_LOG=");
        out_line(logbuf);
        fail_rc("clBuildProgram", rc, 38);
    }

    out_line("stage=clCreateKernel");
    kernel = clCreateKernel(program, "add", &err);
    if (!kernel || err != CL_SUCCESS)
        fail_rc("clCreateKernel", err, 39);

    rc = clSetKernelArg(kernel, 0, sizeof(ba), &ba);
    if (rc != CL_SUCCESS) fail_rc("clSetKernelArg(0)", rc, 40);
    rc = clSetKernelArg(kernel, 1, sizeof(bb), &bb);
    if (rc != CL_SUCCESS) fail_rc("clSetKernelArg(1)", rc, 41);
    rc = clSetKernelArg(kernel, 2, sizeof(bc), &bc);
    if (rc != CL_SUCCESS) fail_rc("clSetKernelArg(2)", rc, 42);

    out_line("stage=clEnqueueWriteBuffer");
    rc = clEnqueueWriteBuffer(queue, ba, CL_TRUE, 0, sizeof(a), a,
                              0, (const cl_event *)0, (cl_event *)0);
    if (rc != CL_SUCCESS) fail_rc("clEnqueueWriteBuffer(a)", rc, 43);
    rc = clEnqueueWriteBuffer(queue, bb, CL_TRUE, 0, sizeof(b), b,
                              0, (const cl_event *)0, (cl_event *)0);
    if (rc != CL_SUCCESS) fail_rc("clEnqueueWriteBuffer(b)", rc, 44);

    out_line("stage=clEnqueueNDRangeKernel");
    rc = clEnqueueNDRangeKernel(queue, kernel, 1,
                                (const size_t_cl *)0, &global,
                                (const size_t_cl *)0, 0,
                                (const cl_event *)0, (cl_event *)0);
    if (rc != CL_SUCCESS)
        fail_rc("clEnqueueNDRangeKernel", rc, 45);

    rc = clFinish(queue);
    if (rc != CL_SUCCESS)
        fail_rc("clFinish", rc, 46);

    out_line("stage=clEnqueueReadBuffer");
    rc = clEnqueueReadBuffer(queue, bc, CL_TRUE, 0, sizeof(c), c,
                             0, (const cl_event *)0, (cl_event *)0);
    if (rc != CL_SUCCESS)
        fail_rc("clEnqueueReadBuffer", rc, 47);

    out_raw("RESULT=");
    out_int(c[0]); out_raw(",");
    out_int(c[1]); out_raw(",");
    out_int(c[2]); out_raw(",");
    out_int(c[3]); out_raw("\n");

    if (kernel) (void)clReleaseKernel(kernel);
    if (program) (void)clReleaseProgram(program);
    if (bc) (void)clReleaseMemObject(bc);
    if (bb) (void)clReleaseMemObject(bb);
    if (ba) (void)clReleaseMemObject(ba);
    if (queue) (void)clReleaseCommandQueue(queue);
    if (context) (void)clReleaseContext(context);

    if (c[0] != 11 || c[1] != 22 || c[2] != 33 || c[3] != 44) {
        out_line("FAIL GPU_OPENCL_RESULT_MISMATCH");
        raw_exit(48);
    }

    out_line("PASS GPU_OPENCL_OK");
    raw_exit(0);
}
