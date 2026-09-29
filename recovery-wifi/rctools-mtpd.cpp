#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

// ABI-compatible minimal declaration for TeamWin android-10.0 libtwrpmtp-ffs.
// The real class contains exactly two pointers followed by an int and has no
// virtual methods. We intentionally call only ctor + forkserver(), avoiding
// std::string/libc++ objects across the launcher/library boundary.
class twrpMtp {
public:
    explicit twrpMtp(int debug_enabled = 0);
    pid_t forkserver(int mtppipe[2]);
private:
    void* mtpstorages;
    void* s;
    int mtp_read_pipe;
};

struct mtpmsg {
    int message_type;
    unsigned int storage_id;
    char display[1024];
    char path[1024];
    uint64_t maxFileSize;
};

static const int MTP_MESSAGE_ADD_STORAGE = 1;
static volatile sig_atomic_t g_stop = 0;
static pid_t g_child = -1;

static void on_signal(int) {
    g_stop = 1;
    if (g_child > 0) {
        kill(g_child, SIGTERM);
    }
}

static int write_full(int fd, const void* data, size_t size) {
    const char* p = static_cast<const char*>(data);
    while (size) {
        ssize_t n = write(fd, p, size);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        p += n;
        size -= static_cast<size_t>(n);
    }
    return 0;
}

static int write_pidfile(const char* path, pid_t pid) {
    FILE* f = fopen(path, "w");
    if (!f) return -1;
    int ok = fprintf(f, "%d\n", static_cast<int>(pid)) > 0 ? 0 : -1;
    fclose(f);
    return ok;
}

int main(int argc, char** argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s PATH DISPLAY CHILD_PIDFILE\n", argv[0]);
        return 2;
    }

    const char* storage_path = argv[1];
    const char* display = argv[2];
    const char* child_pidfile = argv[3];

    if (storage_path[0] != '/' || strlen(storage_path) >= sizeof(((mtpmsg*)0)->path)) {
        fprintf(stderr, "invalid MTP storage path\n");
        return 2;
    }
    if (!display[0] || strlen(display) >= sizeof(((mtpmsg*)0)->display)) {
        fprintf(stderr, "invalid MTP display name\n");
        return 2;
    }

    int pipefd[2];
    if (pipe(pipefd) != 0) {
        perror("pipe");
        return 1;
    }

    // Keep default signal dispositions while forkserver() creates the MTP
    // child. Only the supervising parent installs handlers afterwards, so a
    // SIGTERM sent to the child really terminates the server.
    twrpMtp mtp(0);
    g_child = mtp.forkserver(pipefd);
    if (g_child <= 0) {
        fprintf(stderr, "twrpMtp::forkserver failed\n");
        close(pipefd[0]);
        close(pipefd[1]);
        return 1;
    }

    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    signal(SIGHUP, on_signal);

    close(pipefd[0]);

    mtpmsg msg;
    memset(&msg, 0, sizeof(msg));
    msg.message_type = MTP_MESSAGE_ADD_STORAGE;
    msg.storage_id = 0x00010001U;
    msg.maxFileSize = 0;
    strncpy(msg.display, display, sizeof(msg.display) - 1);
    strncpy(msg.path, storage_path, sizeof(msg.path) - 1);

    if (write_full(pipefd[1], &msg, sizeof(msg)) != 0) {
        perror("write mtp storage");
        kill(g_child, SIGTERM);
        waitpid(g_child, nullptr, 0);
        close(pipefd[1]);
        return 1;
    }

    if (write_pidfile(child_pidfile, g_child) != 0) {
        perror("write child pidfile");
        kill(g_child, SIGTERM);
        waitpid(g_child, nullptr, 0);
        close(pipefd[1]);
        return 1;
    }

    fprintf(stdout, "MTP server child pid=%d storage=%s display=%s\n",
            static_cast<int>(g_child), storage_path, display);
    fflush(stdout);

    int status = 0;
    while (!g_stop) {
        pid_t w = waitpid(g_child, &status, 0);
        if (w == g_child) break;
        if (w < 0 && errno == EINTR) continue;
        if (w < 0) {
            perror("waitpid");
            break;
        }
    }

    if (g_stop && g_child > 0) {
        kill(g_child, SIGKILL);
        waitpid(g_child, &status, 0);
    }

    unlink(child_pidfile);
    close(pipefd[1]);
    return 0;
}
