#ifndef SYM_MONOTONIC_H
#define SYM_MONOTONIC_H

#include <stdint.h>

#if defined(_WIN32)
#  include <windows.h>

static int64_t sym_monotonic_milliseconds(void) {
    LARGE_INTEGER counter;
    LARGE_INTEGER frequency;
    if (!QueryPerformanceCounter(&counter) ||
        !QueryPerformanceFrequency(&frequency) ||
        frequency.QuadPart <= 0) {
        return (int64_t)GetTickCount();
    }
    return (int64_t)(
        (counter.QuadPart / frequency.QuadPart) * 1000 +
        ((counter.QuadPart % frequency.QuadPart) * 1000) /
            frequency.QuadPart);
}

#elif defined(__APPLE__)
#  include <mach/mach_time.h>

static int64_t sym_monotonic_milliseconds(void) {
    mach_timebase_info_data_t scale;
    uint64_t ticks = mach_absolute_time();
    if (mach_timebase_info(&scale) != KERN_SUCCESS || scale.denom == 0) {
        return 0;
    }
    return (int64_t)(((long double)ticks * (long double)scale.numer) /
        ((long double)scale.denom * 1000000.0L));
}

#else
#  include <time.h>

static int64_t sym_monotonic_milliseconds(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value) != 0) {
        return 0;
    }
    return (int64_t)value.tv_sec * 1000 + (int64_t)value.tv_nsec / 1000000;
}
#endif

#endif
