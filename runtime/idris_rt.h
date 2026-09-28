/* The runtime's C interface (TC-RT-1, LOW-RT-1; docs/plan.md sections 3,
 * 4.3, 5.4 and 5.6).
 *
 * Every helper that idr-lower calls is here. Programs join the runtime's
 * bitcode by LTO (TC-LINK-1), so what a program does not call is not in its
 * executable. idris-mlir-cc links the same code natively: the folders of
 * the string and big ops call it, and so does the code idr-eval JITs, so a
 * primitive has one implementation at compile time and at runtime.
 *
 * The layouts below are shared with idr-lower (foreign/idr/lib/Lower), which
 * writes constants of them into static data. */
#ifndef IDRIS_RT_H
#define IDRIS_RT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
#define IDRIS_RT_NORETURN [[noreturn]]
extern "C" {
#else
#define IDRIS_RT_NORETURN _Noreturn
#endif

/* Every heap object starts with this header (plan section 4.3). A count of 0
 * marks static data (LOW-CONST-1): constants in .rodata, never freed. The
 * second word depends on the object: a string's ASCII flag, a box's
 * constructor tag, a closure's label. */
typedef struct idris_rt_header {
  uint32_t count;
  uint32_t info;
} idris_rt_header;

/* A string (LOW-STR-2): the header, whose info is 1 when every byte is ASCII,
 * the byte length, the number of scalar values, then the UTF-8 bytes. */
typedef struct idris_rt_str {
  idris_rt_header header;
  uint64_t bytes;
  uint64_t scalars;
} idris_rt_str;

/* A big (LOW-BIG-1) is one 64-bit word. An odd word holds a 63-bit integer
 * shifted left by one; an even word points to an idris_rt_bignum, which holds
 * any integer outside that range. A value is small exactly when it fits, so
 * each integer has one representation. */
typedef int64_t idris_rt_big;

/* A big outside the small range: the header, then a GMP integer whose limbs
 * GMP allocates (or, in static data, point to a constant limb array). The
 * GMP integer is spelled out so that this header needs no gmp.h:
 * __mpz_struct is { int alloc; int size; mp_limb_t *d; }. */
typedef struct idris_rt_bignum {
  idris_rt_header header;
  int32_t alloc;
  int32_t size;
  uint64_t *limbs;
} idris_rt_bignum;

/* A box (LOW-BOX-1) is the header, whose info is the constructor tag, then
 * the constructor's fields. A closure (LOW-CLOS-1) is the header, whose info
 * is the label (idr-lower numbers the functions closures name), then the
 * code pointer, then the captures. Their field layouts are idr-lower's. */

/* Allocation (TC-RT-3). The size classes with an allocate and a free entry
 * each: every snmalloc size class from 16 bytes to 1 KiB, with
 * SNMALLOC_MIN_ALLOC_STEP_SIZE=8 (plan 5.6), so a cell of an 8-byte header
 * and two fields takes exactly 24 bytes. alloc.cc checks that each is
 * exactly one snmalloc class. */
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

/* A cell of `size` bytes for a box or a closure that idr-lower builds; ends
 * the process with a crash when memory is exhausted. */
void *idris_rt_cell(size_t size);

/* Standard output and input (LOW-IO-1, LOW-IO-2, LOW-IO-4; SEM-IO-2..7).
 * Output goes through one static buffer, flushed when it fills, before every
 * read, before exit and a crash's message, and when main returns. */
void idris_rt_flush(void);
void idris_rt_io_put_str(const idris_rt_str *s);
/* The UTF-8 encoding of the character c. */
void idris_rt_io_put_char(int32_t c);
/* The decimal text of a signed or an unsigned integer, which idr-lower
 * extends to 64 bits as its type's signedness says. */
void idris_rt_io_put_int_s(int64_t value);
void idris_rt_io_put_int_u(uint64_t value);
/* The text of SEM-DBL-5. */
void idris_rt_io_put_double(double value);
/* One UTF-8 encoded scalar value: '\0' at the end of input, U+FFFD for each
 * maximal invalid subsequence (SEM-IO-3). */
int32_t idris_rt_io_get_char(void);
/* One byte, or 255 at the end of input (SEM-IO-7). */
int32_t idris_rt_io_get_byte(void);
/* Writes pending output, then ends the process with status code mod 256
 * (SEM-IO-5). */
IDRIS_RT_NORETURN void idris_rt_io_exit(int64_t code);
/* Writes pending output, then the len bytes of msg to standard error, then
 * ends the process with status 1 (SEM-CRASH-1, LOW-CRASH-1). */
IDRIS_RT_NORETURN void idris_rt_crash(const char *msg, size_t len);

/* Doubles (LOW-DBL-1, LOW-DBL-4). x truncated toward zero, modulo 2^64; x is
 * finite (idr-lower checks it first). */
int64_t idris_rt_to_int(double x);
/* The first character of the text of SEM-DBL-5. */
int32_t idris_rt_double_head(double x);
/* The first character of the decimal text of a signed or unsigned integer. */
int32_t idris_rt_int_head_s(int64_t value);
int32_t idris_rt_int_head_u(uint64_t value);

/* Strings (SEM-STR-*, LOW-STR-2). Strings are immutable; each operation
 * returns a new string or a static one. Preconditions, which idr-lower
 * checks and crashes on before the call: idris_rt_str_index needs
 * 0 <= i < length, idris_rt_str_head and idris_rt_str_tail a nonempty
 * string. */
const idris_rt_str *idris_rt_str_append(const idris_rt_str *a, const idris_rt_str *b);
const idris_rt_str *idris_rt_str_cons(int32_t c, const idris_rt_str *s);
const idris_rt_str *idris_rt_str_from_char(int32_t c);
const idris_rt_str *idris_rt_str_show_s(int64_t value);
const idris_rt_str *idris_rt_str_show_u(uint64_t value);
const idris_rt_str *idris_rt_str_show_f64(double value);
/* The number of scalar values. */
int64_t idris_rt_str_length(const idris_rt_str *s);
int32_t idris_rt_str_index(const idris_rt_str *s, int64_t i);
int32_t idris_rt_str_head(const idris_rt_str *s);
const idris_rt_str *idris_rt_str_tail(const idris_rt_str *s);
/* Chez's string-substr: the scalars from max(0, start), at most max(0, len)
 * of them; "" when the start is past the end. */
const idris_rt_str *idris_rt_str_substr(const idris_rt_str *s, int64_t start, int64_t len);
const idris_rt_str *idris_rt_str_reverse(const idris_rt_str *s);
/* Negative, zero or positive as a is before, equal to or after b in the
 * order of their scalar values (Chez's string<?). */
int32_t idris_rt_str_cmp(const idris_rt_str *a, const idris_rt_str *b);
/* `cast` from String (plan section 3). Which strings are numbers is ours to
 * define:
 * - to Double: the whole string in fast_float's general format, with a
 *   leading `+` allowed, correctly rounded; an exponent out of range gives
 *   the infinity or zero fast_float stores alongside its range error;
 *   anything else is 0;
 * - to an integer: a sign (`+` or `-`) and decimal digits give that integer,
 *   exactly; any other string the Double cast accepts gives its finite value
 *   truncated toward zero, as Chez's exact-truncate does; anything else,
 *   the infinities and NaN included, is 0.
 * idris_rt_str_to_int returns the result modulo 2^64; idr-lower wraps it to
 * the op's width. */
double idris_rt_str_to_double(const idris_rt_str *s);
int64_t idris_rt_str_to_int(const idris_rt_str *s);
/* The string of n bytes of well-formed UTF-8 at p: a new string. */
const idris_rt_str *idris_rt_str_from_utf8(const char *p, size_t n);
/* The UTF-8 bytes of s. */
const char *idris_rt_str_bytes(const idris_rt_str *s);

/* Bigs (LOW-BIG-1): Integer, and the Nat-like types. Division and modulus
 * are Euclidean, as blodwen-euclidDiv and blodwen-euclidMod in the Chez
 * support code (SEM-INT-3), which is also what Idris's evaluator computes;
 * the divisor is nonzero (idr-lower checks it first). The bitwise operations
 * are those of the infinite two's complement representation (Chez's logand,
 * logor and logxor). */
idris_rt_big idris_rt_big_add(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_sub(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_mul(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_div(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_mod(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_and(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_or(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_xor(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_neg(idris_rt_big a);
/* Negative, zero or positive as a < b, a = b or a > b. */
int32_t idris_rt_big_cmp(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_from_int_s(int64_t value);
idris_rt_big idris_rt_big_from_int_u(uint64_t value);
/* The value modulo 2^64; idr-lower wraps it to the op's width. */
int64_t idris_rt_big_to_int(idris_rt_big a);
/* x truncated toward zero; x is finite (idr-lower checks it first). */
idris_rt_big idris_rt_big_from_double(double x);
/* The double nearest to a, ties to even (Chez's exact->inexact). */
double idris_rt_big_to_double(idris_rt_big a);
const idris_rt_str *idris_rt_big_show(idris_rt_big a);
/* The integer cast of idris_rt_str_to_int, without the wrapping. */
idris_rt_big idris_rt_big_from_str(const idris_rt_str *s);

/* Freeing what an operation returned, for callers that own it: the compiler's
 * folders, which turn each result into an attribute. Static data is left
 * alone. */
void idris_rt_str_release(const idris_rt_str *s);
void idris_rt_big_release(idris_rt_big a);

/* Strings over simdutf (plan section 3). */
/* Whether the n bytes at p are well-formed UTF-8. */
bool idris_rt_utf8_valid(const char *p, size_t n);
/* The number of scalar values in n bytes of well-formed UTF-8. */
size_t idris_rt_utf8_count(const char *p, size_t n);
/* Whether the n bytes at p are all ASCII. */
bool idris_rt_ascii(const char *p, size_t n);

/* `cast` from String to Double over the n bytes at p (idris_rt_str_to_double). */
double idris_rt_parse_double(const char *p, size_t n);

/* Points GMP's memory functions at the runtime's allocator (plan 5.3). The
 * big operations call it themselves before GMP first allocates. */
void idris_rt_gmp_init(void);

/* Compile-time evaluation (LOW-JIT-1, EVAL-1). idr-eval runs the calls of a
 * round in a child process, whose JITed code idr-lower wrote in JIT mode:
 * cells come from idris_rt_arena_alloc and a crash is idris_rt_eval_crash.
 * idris_rt_eval_begin, called once in the child, makes every other
 * allocation of the runtime use the arena too. The arena is never freed: the
 * child ends with the round (SEM-EVAL-7: memory management is not
 * observable). */
void idris_rt_eval_begin(int report_fd);
void *idris_rt_arena_alloc(size_t size);
/* Writes msg to the report descriptor, then ends the child with
 * IDRIS_RT_EVAL_CRASHED. */
IDRIS_RT_NORETURN void idris_rt_eval_crash(const char *msg, size_t len);

/* The exit statuses of an evaluation child: its calls crashed, or the
 * machine refused memory (EVAL-1). */
#define IDRIS_RT_EVAL_CRASHED 3
#define IDRIS_RT_EVAL_EXHAUSTED 4

#ifdef __cplusplus
}
#endif

#endif /* IDRIS_RT_H */
