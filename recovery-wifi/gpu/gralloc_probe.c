/*
 * Recovery gralloc HAL discovery probe.
 *
 * Calls the same libhardware hw_get_module("gralloc") entry point used by
 * Android-facing graphics components.  This distinguishes an EGL failure in
 * HAL discovery from KGSL/OpenCL failures.
 */

typedef int hw_status_t;
struct hw_module_t;
extern int hw_get_module(const char *id, const struct hw_module_t **module);

#define SYS_WRITE       64
#define SYS_EXIT_GROUP  94

static long syscall3_probe(long nr, long a0, long a1, long a2)
{
    register long x0 __asm__("x0") = a0;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    register long x8 __asm__("x8") = nr;

    __asm__ volatile("svc 0" : "+r"(x0) : "r"(x1), "r"(x2), "r"(x8) : "memory");
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
    while (s && s[n]) ++n;
    return n;
}

static void out_raw(const char *s)
{
    if (s) (void)syscall3_probe(SYS_WRITE, 1, (long)s, (long)slen(s));
}

static void out_int(int v)
{
    char buf[24];
    unsigned int n;
    int i = 23;
    buf[i--] = 0;
    n = v < 0 ? (unsigned int)(-v) : (unsigned int)v;
    if (!n) { out_raw("0"); return; }
    while (n && i >= 1) { buf[i--] = (char)('0' + (n % 10)); n /= 10; }
    if (v < 0) buf[i--] = '-';
    out_raw(&buf[i + 1]);
}

__attribute__((constructor))
static void run_gralloc_probe(void)
{
    const struct hw_module_t *module = (const struct hw_module_t *)0;
    int rc;

    out_raw("CHANNEL_GPU_GRALLOC_PROBE v1\n");
    out_raw("stage=hw_get_module(gralloc)\n");

    rc = hw_get_module("gralloc", &module);
    out_raw("HW_GET_MODULE_RC=");
    out_int(rc);
    out_raw("\n");

    if (rc != 0 || !module) {
        out_raw("FAIL GRALLOC_HAL_LOAD\n");
        raw_exit(50);
    }

    out_raw("PASS GRALLOC_HAL_OK\n");
    raw_exit(0);
}
