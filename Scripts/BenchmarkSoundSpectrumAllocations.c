// Optional DYLD_INSERT_LIBRARIES probe for BenchmarkSoundSpectrum.swift.
// Counts calls/requested bytes at malloc/calloc/realloc entry points only.
// These counters are not a count of all objects or live/peak heap usage.
#include <stdlib.h>
#include <stdatomic.h>
#include <stdint.h>

static _Atomic uint64_t calls, bytes;
static _Atomic int enabled;
void spectrum_alloc_begin(void) {
    atomic_store(&calls, 0);
    atomic_store(&bytes, 0);
    atomic_store(&enabled, 1);
}
void spectrum_alloc_end(void) { atomic_store(&enabled, 0); }
uint64_t spectrum_alloc_calls(void) { return atomic_load(&calls); }
uint64_t spectrum_alloc_bytes(void) { return atomic_load(&bytes); }
static void record(size_t size) {
    if (atomic_load(&enabled)) {
        atomic_fetch_add(&calls, 1);
        atomic_fetch_add(&bytes, size);
    }
}
static void *probe_malloc(size_t size) { record(size); return malloc(size); }
static void *probe_calloc(size_t count, size_t size) { record(count * size); return calloc(count, size); }
static void *probe_realloc(void *ptr, size_t size) { record(size); return realloc(ptr, size); }
#define INTERPOSE(replacement, original) \
    __attribute__((used)) static struct { const void *new_fn; const void *old_fn; } \
    interpose_##original __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)&replacement, (const void *)&original \
    }
INTERPOSE(probe_malloc, malloc);
INTERPOSE(probe_calloc, calloc);
INTERPOSE(probe_realloc, realloc);
