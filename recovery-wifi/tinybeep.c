/*
 * Low-level recovery speaker test for Motorola Channel.
 * 48 kHz stereo S16_LE, 1 kHz, 250 ms, deliberately low amplitude.
 */
#include <tinyalsa/asoundlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const int16_t sine_1khz_48k[48] = {
      0,   91,  181,  268,  350,  426,  495,  555,
    606,  647,  676,  694,  700,  694,  676,  647,
    606,  555,  495,  426,  350,  268,  181,   91,
      0,  -91, -181, -268, -350, -426, -495, -555,
   -606, -647, -676, -694, -700, -694, -676, -647,
   -606, -555, -495, -426, -350, -268, -181,  -91
};

static void usage(const char *argv0)
{
    fprintf(stderr, "usage: %s [-D card] [-d device]\n", argv0);
}

int tinybeep_main(int argc, char **argv)
{
    unsigned int card = 0;
    unsigned int device = 0;
    unsigned int i;
    unsigned int frame = 0;
    const unsigned int total_frames = 48000 / 4;
    const unsigned int chunk_frames = 1024;
    int16_t samples[1024 * 2];
    struct pcm_config config;
    struct pcm *pcm;

    for (i = 1; i < (unsigned int)argc; i++) {
        if (!strcmp(argv[i], "-D") && i + 1 < (unsigned int)argc) {
            card = (unsigned int)atoi(argv[++i]);
        } else if (!strcmp(argv[i], "-d") && i + 1 < (unsigned int)argc) {
            device = (unsigned int)atoi(argv[++i]);
        } else if (!strcmp(argv[i], "-h") || !strcmp(argv[i], "--help")) {
            usage(argv[0]);
            return 0;
        } else {
            usage(argv[0]);
            return 2;
        }
    }

    memset(&config, 0, sizeof(config));
    config.channels = 2;
    config.rate = 48000;
    config.period_size = chunk_frames;
    config.period_count = 2;
    config.format = PCM_FORMAT_S16_LE;
    config.start_threshold = chunk_frames;
    config.stop_threshold = chunk_frames * config.period_count;
    config.silence_threshold = 0;
    config.silence_size = 0;

    pcm = pcm_open(card, device, PCM_OUT, &config);
    if (!pcm || !pcm_is_ready(pcm)) {
        fprintf(stderr, "tinybeep: unable to open PCM %u,%u: %s\n",
                card, device, pcm ? pcm_get_error(pcm) : "allocation failed");
        if (pcm)
            pcm_close(pcm);
        return 1;
    }

    while (frame < total_frames) {
        unsigned int n = total_frames - frame;
        unsigned int f;
        if (n > chunk_frames)
            n = chunk_frames;

        for (f = 0; f < n; f++) {
            int16_t v = sine_1khz_48k[(frame + f) % 48];
            samples[f * 2] = v;
            samples[f * 2 + 1] = v;
        }

        if (pcm_writei(pcm, samples, n) < 0) {
            fprintf(stderr, "tinybeep: PCM write failed: %s\n", pcm_get_error(pcm));
            pcm_close(pcm);
            return 1;
        }
        frame += n;
    }

    pcm_close(pcm);
    return 0;
}
