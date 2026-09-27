/* The runtime's C interface (TC-RT-1; docs/plan.md sections 3, 5.4, 5.6).
 *
 * Nothing in the compiler calls it yet: milestone M1 does. Every program's
 * LTO module links it from the runtime's bitcode (TC-LINK-1), so what a
 * program does not call is not in its executable. */
#ifndef IDRIS_RT_H
#define IDRIS_RT_H

#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* The size classes with an allocate and a free entry each: every snmalloc
 * size class from 16 bytes to 1 KiB, with SNMALLOC_MIN_ALLOC_STEP_SIZE=8
 * (plan 5.6), so a cell of an 8-byte header and two fields takes exactly 24
 * bytes. alloc.cc checks that each is exactly one snmalloc class. */
#define IDRIS_RT_SIZE_CLASSES(X)                                               \
  X(16) X(24) X(32) X(40) X(48) X(56) X(64) X(80) X(96) X(112) X(128)          \
  X(160) X(192) X(224) X(256) X(320) X(384) X(448) X(512) X(640) X(768)        \
  X(896) X(1024)

/* idris_rt_alloc_S returns S uninitialized bytes from the calling thread's
 * heap, or NULL when memory is exhausted; idris_rt_free_S frees a block that
 * idris_rt_alloc_S returned, from any thread. */
#define IDRIS_RT_DECLARE_SIZE_CLASS(S)                                          \
  void *idris_rt_alloc_##S(void);                                              \
  void idris_rt_free_##S(void *block);
IDRIS_RT_SIZE_CLASSES(IDRIS_RT_DECLARE_SIZE_CLASS)
#undef IDRIS_RT_DECLARE_SIZE_CLASS

/* Any other size, known only at runtime. */
void *idris_rt_alloc(size_t size);
void idris_rt_free(void *block);

/* Strings (plan section 3), over simdutf. */
/* Whether the n bytes at p are well-formed UTF-8. */
bool idris_rt_utf8_valid(const char *p, size_t n);
/* The number of scalar values in n bytes of well-formed UTF-8. */
size_t idris_rt_utf8_count(const char *p, size_t n);
/* Whether the n bytes at p are all ASCII. */
bool idris_rt_ascii(const char *p, size_t n);

/* `cast` from String to Double (plan section 3), over fast_float: the whole
 * string in fast_float's general format with a leading `+` allowed, correctly
 * rounded; an exponent out of range gives the infinity or zero fast_float
 * stores; anything else is 0. */
double idris_rt_parse_double(const char *p, size_t n);

/* Points GMP's memory functions at the runtime's allocator (plan 5.3). */
void idris_rt_gmp_init(void);

#ifdef __cplusplus
}
#endif

#endif /* IDRIS_RT_H */
