// ticbench: load a libretro core, run a cart unthrottled (no frame limit, no display), time it.
// usage:
//   ticbench <core.so> <cart.tic> <warmup_frames> <max_frames> <max_seconds>
//       -> fps and ms/frame. Input: a fixed script of button taps (gets past title screens).
//   ticbench <core.so> <cart.tic> bunny <hold1> <hold2> <frames> <max_seconds>
//       -> for TIC-80 bunnymark carts: hold UP for <hold1> frames (adds bunnies), measure,
//          hold UP <hold2> more frames, measure again. Prints ms/frame at both levels.
//   ticbench <core.so> <cart.tic> hash <frames>
//       -> prints a checksum of every frame (same scripted input) - to verify two cores render
//          identically. Optional: <frame> <file.ppm> saves that frame as an image.
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include "libretro.h"

static unsigned frame_no;
static int bunny_mode, hold_up;
static retro_frame_time_callback_t frame_time_cb;
static char sysdir[512] = "/tmp";

static void log_cb(enum retro_log_level level, const char *fmt, ...) {
    if (level < RETRO_LOG_WARN) return;
    va_list ap; va_start(ap, fmt); vfprintf(stderr, fmt, ap); va_end(ap);
}

static bool env_cb(unsigned cmd, void *data) {
    switch (cmd) {
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
        ((struct retro_log_callback *)data)->log = log_cb; return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: return true;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
        *(const char **)data = sysdir; return true;
    case RETRO_ENVIRONMENT_GET_CAN_DUPE: *(bool *)data = true; return true;
    case RETRO_ENVIRONMENT_SET_FRAME_TIME_CALLBACK:
        frame_time_cb = ((const struct retro_frame_time_callback *)data)->callback; return true;
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_GEOMETRY:
    case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME:
        return true;
    default: return false;
    }
}

static volatile uint32_t sink;
static int hash_mode;
static const char *dump_path;      // hash mode: optionally save frame <dump_frame> as PPM
static unsigned dump_frame;
static uint64_t frame_hash;
static void video_cb(const void *d, unsigned w, unsigned h, size_t pitch) {
    // touch the frame like a frontend would (prevents the core skipping work)
    if (d) sink += ((const uint32_t *)d)[(h / 2) * (pitch / 4) + w / 2];
    if (hash_mode && d) {           // FNV-1a over the visible frame
        uint64_t x = 1469598103934665603ULL;
        for (unsigned y = 0; y < h; y++) {
            const uint32_t *row = (const uint32_t *)((const char *)d + y * pitch);
            for (unsigned i = 0; i < w; i++) { x ^= row[i] & 0xFFFFFF; x *= 1099511628211ULL; }
        }
        frame_hash = x;
        if (dump_path && frame_no == dump_frame) {   // save this frame as a PPM image
            FILE *f = fopen(dump_path, "wb");
            if (f) {
                fprintf(f, "P6\n%u %u\n255\n", w, h);
                for (unsigned y = 0; y < h; y++)
                    for (unsigned i = 0; i < w; i++) {
                        uint32_t p = ((const uint32_t *)((const char *)d + y * pitch))[i];
                        unsigned char rgb[3] = { p >> 16, p >> 8, p };
                        fwrite(rgb, 1, 3, f);
                    }
                fclose(f);
            }
        }
    }
}
static void audio_cb(int16_t l, int16_t r) { (void)l; (void)r; }
static size_t audio_batch_cb(const int16_t *d, size_t f) { (void)d; return f; }
static void input_poll_cb(void) {}

// Fixed, deterministic input script so every core sees the same presses:
// tap A/B/START regularly to get through menus, and walk/turn left-right.
static int16_t input_state_cb(unsigned port, unsigned dev, unsigned idx, unsigned id) {
    (void)idx;
    if (port != 0 || dev != RETRO_DEVICE_JOYPAD) return 0;
    if (bunny_mode) return id == RETRO_DEVICE_ID_JOYPAD_UP && hold_up;
    unsigned f = frame_no;
    switch (id) {
    case RETRO_DEVICE_ID_JOYPAD_A:     return (f % 40) < 4;
    case RETRO_DEVICE_ID_JOYPAD_B:     return (f % 97) < 3;
    case RETRO_DEVICE_ID_JOYPAD_START: return (f % 180) < 4;
    case RETRO_DEVICE_ID_JOYPAD_UP:    return (f % 240) >= 60 && (f % 240) < 150;
    case RETRO_DEVICE_ID_JOYPAD_RIGHT: return (f % 300) < 120;
    case RETRO_DEVICE_ID_JOYPAD_LEFT:  return (f % 300) >= 180 && (f % 300) < 260;
    default: return 0;
    }
}

static double now(void) {
    struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec / 1e9;
}

static void (*p_run)(void);
static void run_frame(void) {
    if (frame_time_cb) frame_time_cb(16667);   // tell the core 1/60 s passed (time() works)
    p_run(); frame_no++;
}

// run up to maxf frames or maxs seconds; return ms/frame, worst frame ms in *worst
static double measure(unsigned maxf, double maxs, double *worst, unsigned *count) {
    double t0 = now(), prev = t0; unsigned n = 0; *worst = 0;
    while (n < maxf) {
        run_frame(); n++;
        double t = now();
        if (t - prev > *worst) *worst = t - prev;
        prev = t;
        if (t - t0 >= maxs) break;
    }
    *count = n;
    return (now() - t0) * 1000.0 / n;
}

#define SYM(name) do { *(void **)&p_##name = dlsym(h, #name); \
    if (!p_##name) { fprintf(stderr, "missing %s\n", #name); return 2; } } while (0)

int main(int argc, char **argv) {
    if (argc < 5) { fprintf(stderr, "usage: see top of ticbench.c\n"); return 1; }
    const char *core = argv[1], *cart = argv[2];
    unsigned warm = 0, maxf = 0, h1 = 0, h2 = 0, bf = 0; double maxs;
    unsigned hframes = 0;
    if (!strcmp(argv[3], "hash")) {
        hash_mode = 1; hframes = atoi(argv[4]); maxs = 0;
        if (argc >= 7) { dump_frame = atoi(argv[5]); dump_path = argv[6]; }
    } else if (!strcmp(argv[3], "bunny")) {
        if (argc < 8) { fprintf(stderr, "bunny mode needs: hold1 hold2 frames max_seconds\n"); return 1; }
        bunny_mode = 1; h1 = atoi(argv[4]); h2 = atoi(argv[5]); bf = atoi(argv[6]); maxs = atof(argv[7]);
    } else {
        warm = atoi(argv[3]); maxf = atoi(argv[4]); maxs = atof(argv[5]);
    }

    // Some language runtimes print to stdout every frame (e.g. Scheme bunnymark) - silence the
    // core's stdout so it doesn't mix with our results or cost time; results go to a saved fd.
    int outfd = dup(1);
    int devnull = open("/dev/null", O_WRONLY);
    if (devnull >= 0) { dup2(devnull, 1); close(devnull); }
    FILE *res = fdopen(outfd, "w");

    void *h = dlopen(core, RTLD_NOW | RTLD_LOCAL);
    if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 2; }

    void (*p_retro_set_environment)(retro_environment_t);
    void (*p_retro_set_video_refresh)(retro_video_refresh_t);
    void (*p_retro_set_audio_sample)(retro_audio_sample_t);
    void (*p_retro_set_audio_sample_batch)(retro_audio_sample_batch_t);
    void (*p_retro_set_input_poll)(retro_input_poll_t);
    void (*p_retro_set_input_state)(retro_input_state_t);
    void (*p_retro_init)(void);
    void (*p_retro_get_system_info)(struct retro_system_info *);
    bool (*p_retro_load_game)(const struct retro_game_info *);
    void (*p_retro_run)(void);
    SYM(retro_set_environment); SYM(retro_set_video_refresh); SYM(retro_set_audio_sample);
    SYM(retro_set_audio_sample_batch); SYM(retro_set_input_poll); SYM(retro_set_input_state);
    SYM(retro_init); SYM(retro_get_system_info); SYM(retro_load_game); SYM(retro_run);
    p_run = p_retro_run;

    p_retro_set_environment(env_cb);
    p_retro_set_video_refresh(video_cb);
    p_retro_set_audio_sample(audio_cb);
    p_retro_set_audio_sample_batch(audio_batch_cb);
    p_retro_set_input_poll(input_poll_cb);
    p_retro_set_input_state(input_state_cb);
    p_retro_init();

    struct retro_system_info si = {0};
    p_retro_get_system_info(&si);

    FILE *f = fopen(cart, "rb");
    if (!f) { perror(cart); return 3; }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    void *buf = malloc(n);
    if (fread(buf, 1, n, f) != (size_t)n) { perror("read"); return 3; }
    fclose(f);
    struct retro_game_info gi = { cart, buf, (size_t)n, NULL };
    if (!p_retro_load_game(&gi)) { fprintf(stderr, "load_game failed\n"); return 4; }

    const char *ver = si.library_version ? si.library_version : "?";
    double worst; unsigned cnt;
    if (hash_mode) {
        for (unsigned i = 0; i < hframes; i++) {
            run_frame();
            fprintf(res, "%u %016llx\n", i, (unsigned long long)frame_hash);
        }
    } else if (bunny_mode) {
        hold_up = 1; for (unsigned i = 0; i < h1; i++) run_frame();
        hold_up = 0; for (unsigned i = 0; i < 10; i++) run_frame();
        double ms1 = measure(bf, maxs, &worst, &cnt);
        hold_up = 1; for (unsigned i = 0; i < h2; i++) run_frame();
        hold_up = 0; for (unsigned i = 0; i < 10; i++) run_frame();
        double ms2 = measure(bf, maxs, &worst, &cnt);
        fprintf(res, "%s\tbunny\thold %u: %.3f ms/frame\thold +%u: %.3f ms/frame\n", ver, h1, ms1, h2, ms2);
    } else {
        for (unsigned i = 0; i < warm; i++) run_frame();
        double ms = measure(maxf, maxs, &worst, &cnt);
        fprintf(res, "%s\t%.1f fps\t%.3f ms/frame\tworst %.1f ms\t(%u frames)\n", ver, 1000.0 / ms, ms, worst * 1000.0, cnt);
    }
    fflush(res);
    _exit(0); // skip core teardown; we only care about the measurement
}
