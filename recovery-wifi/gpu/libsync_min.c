/*
 * Minimal recovery libsync ABI for Channel's Qualcomm KGSL userspace.
 *
 * Source-only replacement for the libsync.so normally supplied by Android
 * system.  The proprietary SDM632 libgsl.so imports only sync_wait() and
 * sync_merge(); both are implemented directly on the kernel sync_file UAPI.
 *
 * No glibc/Bionic link dependency is baked into this DSO.  errno is updated
 * through Bionic's already-loaded __errno() when available.
 */

typedef signed int s32;
typedef unsigned int u32;
typedef unsigned long u64;

#define SYS_IOCTL       29
#define SYS_PPOLL       73

#define EINTR_VALUE      4
#define ETIME_VALUE     62
#define POLLIN_VALUE  0x0001

struct pollfd_min {
    int fd;
    short events;
    short revents;
};

struct timespec_min {
    long tv_sec;
    long tv_nsec;
};

struct sync_merge_data_min {
    char name[32];
    s32 fd2;
    s32 fence;
    u32 flags;
    u32 pad;
};

#define IOC_NRBITS       8
#define IOC_TYPEBITS     8
#define IOC_SIZEBITS    14
#define IOC_NRSHIFT      0
#define IOC_TYPESHIFT    (IOC_NRSHIFT + IOC_NRBITS)
#define IOC_SIZESHIFT    (IOC_TYPESHIFT + IOC_TYPEBITS)
#define IOC_DIRSHIFT     (IOC_SIZESHIFT + IOC_SIZEBITS)
#define IOC_WRITE        1U
#define IOC_READ         2U
#define IOC(dir,type,nr,size) \
    (((dir) << IOC_DIRSHIFT) | ((type) << IOC_TYPESHIFT) | \
     ((nr) << IOC_NRSHIFT) | ((size) << IOC_SIZESHIFT))
#define SYNC_IOC_MERGE \
    IOC(IOC_READ | IOC_WRITE, '>', 3, sizeof(struct sync_merge_data_min))

extern int *__errno(void) __attribute__((weak));

static void set_errno_min(int e)
{
    if (__errno) {
        int *p = __errno();
        if (p)
            *p = e;
    }
}

static long syscall3_min(long nr, long a0, long a1, long a2)
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

static long syscall5_min(long nr, long a0, long a1, long a2, long a3, long a4)
{
    register long x0 __asm__("x0") = a0;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    register long x3 __asm__("x3") = a3;
    register long x4 __asm__("x4") = a4;
    register long x8 __asm__("x8") = nr;

    __asm__ volatile(
        "svc 0"
        : "+r"(x0)
        : "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x8)
        : "memory");

    return x0;
}

static int syscall_result_min(long r)
{
    if (r < 0 && r >= -4095) {
        set_errno_min((int)-r);
        return -1;
    }
    return (int)r;
}

__attribute__((visibility("default")))
int sync_wait(int fd, int timeout_ms)
{
    struct pollfd_min pfd;
    struct timespec_min ts;
    struct timespec_min *tsp;

    pfd.fd = fd;
    pfd.events = POLLIN_VALUE;
    pfd.revents = 0;

    if (timeout_ms < 0) {
        tsp = (struct timespec_min *)0;
    } else {
        ts.tv_sec = timeout_ms / 1000;
        ts.tv_nsec = (long)(timeout_ms % 1000) * 1000000L;
        tsp = &ts;
    }

    for (;;) {
        long r = syscall5_min(
            SYS_PPOLL,
            (long)&pfd,
            1,
            (long)tsp,
            0,
            0);

        if (r > 0)
            return 0;

        if (r == 0) {
            set_errno_min(ETIME_VALUE);
            return -1;
        }

        if (r == -EINTR_VALUE)
            continue;

        return syscall_result_min(r);
    }
}

__attribute__((visibility("default")))
int sync_merge(const char *name, int fd1, int fd2)
{
    struct sync_merge_data_min data;
    int i;

    for (i = 0; i < 32; ++i)
        data.name[i] = 0;

    if (name) {
        for (i = 0; i < 31 && name[i]; ++i)
            data.name[i] = name[i];
    }

    data.fd2 = fd2;
    data.fence = -1;
    data.flags = 0;
    data.pad = 0;

    if (syscall_result_min(syscall3_min(
            SYS_IOCTL,
            fd1,
            (long)SYNC_IOC_MERGE,
            (long)&data)) < 0)
        return -1;

    return data.fence;
}
