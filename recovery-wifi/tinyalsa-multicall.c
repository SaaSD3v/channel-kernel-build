/*
 * TinyALSA recovery multicall launcher.
 * Links TinyALSA and all recovery audio utilities into one static executable
 * so libc/libtinyalsa are paid only once in the kernel internal initramfs.
 */
#include <stdio.h>
#include <string.h>

int tinyplay_main(int argc, char **argv);
int tinycap_main(int argc, char **argv);
int tinymix_main(int argc, char **argv);
int tinypcminfo_main(int argc, char **argv);
int tinybeep_main(int argc, char **argv);

static const char *applet_name(const char *arg0)
{
    const char *p = strrchr(arg0 ? arg0 : "", '/');
    return p ? p + 1 : (arg0 ? arg0 : "");
}

int main(int argc, char **argv)
{
    const char *name = applet_name(argv[0]);

    if (!strcmp(name, "tinyplay"))
        return tinyplay_main(argc, argv);
    if (!strcmp(name, "tinycap"))
        return tinycap_main(argc, argv);
    if (!strcmp(name, "tinymix"))
        return tinymix_main(argc, argv);
    if (!strcmp(name, "tinypcminfo"))
        return tinypcminfo_main(argc, argv);
    if (!strcmp(name, "tinybeep"))
        return tinybeep_main(argc, argv);

    fprintf(stderr,
            "TinyALSA recovery multicall. Invoke as tinymix, tinyplay, "
            "tinycap, tinypcminfo or tinybeep.\n");
    return 2;
}
