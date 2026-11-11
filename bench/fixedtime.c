// LD_PRELOAD shim for verify-render.sh: a fixed clock and fixed "random" bytes,
// so carts that seed their RNG from the time render deterministically.
#define _GNU_SOURCE
#include <time.h>
#include <sys/time.h>
#include <string.h>
#include <sys/types.h>
time_t time(time_t *t) { if (t) *t = 1700000000; return 1700000000; }
int gettimeofday(struct timeval *restrict tv, struct timezone *restrict tz) { (void)tz; if (tv) { tv->tv_sec = 1700000000; tv->tv_usec = 0; } return 0; }
int clock_gettime(clockid_t c, struct timespec *ts) { (void)c; ts->tv_sec = 1700000000; ts->tv_nsec = 0; return 0; }
clock_t clock(void) { return 0; }
ssize_t getrandom(void *buf, size_t n, unsigned flags) { (void)flags; memset(buf, 7, n); return (ssize_t)n; }
