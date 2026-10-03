/* The runtime's C interface.
 *
 * Every helper that idr-lower calls is here. A program inlines the
 * runtime's bitcode where that pays and links the rest natively, so what a
 * program does not call is not in its executable. idris-mlir-cc links the
 * same code natively: the folders of the string and big ops call it, and so
 * does the code idr-eval JITs, so a primitive has one implementation at
 * compile time and at runtime.
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

/* Every heap object starts with this header.
 *
 * count is how many owned references the object has, or one of two marks:
 * - 0: persistent. Static data (constants in .rodata and .data), the results
 *   of compile-time evaluation and the cells of its arena are never counted
 *   and never freed, and everything a persistent object points to is
 *   persistent too, so a persistent object needs no count at all.
 * - 1 to UINT32_MAX - 1: owned references, counted with plain arithmetic,
 *   since a program is single-threaded.
 * - UINT32_MAX: saturated. A count that would overflow stops there, and the
 *   object is never decremented or freed: an overflow leaks the object
 *   instead of freeing it while it is still in use.
 *
 * info is tag | objs << 16 | kind << 24, with bit 31 marking a stack cell.
 * Freeing reads only objs, kind and bit 31, so the runtime frees any cell
 * without knowing its type.
 * - tag (bits 0-15): a box's constructor tag, a string's ASCII flag in bit 0
 *   (set only when every byte is ASCII), an array's element size in bytes;
 *   0 for a closure, whose code pointer says what it is, and for a bignum.
 * - objs (bits 16-23): the number of object slots, one word
 *   (IDRIS_RT_WORD_BYTES) each. A box's are the first objs slots right after
 *   the header; a closure's are the first objs slots after its code pointer,
 *   which is right after the header.
 *   Strings and bignums have none. An array's are per element: its first
 *   objs words (idris_rt_array).
 * - kind (bits 24-30): one of the IDRIS_RT_KIND_ values.
 * - bit 31: a stack cell, which the compiler builds in a frame; its memory
 *   belongs to that frame and it is never a live cell (idris_rt_live_cells).
 *   When its count reaches 0 its object slots are released but its memory is
 *   not freed, and the live-cell count does not change. A stack cell is
 *   never exclusive (idris_rt_is_unique): a callee it is lent
 *   to could otherwise reuse its memory for a result that outlives the frame
 *   holding it.
 * idris_rt_info builds the word, and the accessors below take it apart. It
 * does not check its arguments: idr-lower builds every word it writes
 * through its CellInfo, which exists only for a tag below IDRIS_RT_TAG_LIMIT
 * and an object count below IDRIS_RT_OBJS_LIMIT, so that no field of a word
 * the compiler writes overflows into the next.
 *
 * An object slot holds a counted reference: a pointer to an object, NULL (an
 * unused pointer slot of an unboxed sum), or an odd word (a small Integer or
 * Nat, as idris_rt_big has them). A cell's other fields come after its object
 * slots, so the slots are all the runtime needs to find. */
typedef struct idris_rt_header {
  uint32_t count;
  uint32_t info;
} idris_rt_header;

/* A word: a pointer, an object slot, the header. The compiler places object
 * slots by the target's data layout and rejects a target whose pointers are
 * not words of this size, so every target the runtime is built for must
 * have them: x86_64 Linux and arm64 macOS are both LP64. */
#define IDRIS_RT_WORD_BYTES 8u
#ifdef __cplusplus
#define IDRIS_RT_STATIC_ASSERT static_assert
#define IDRIS_RT_ALIGNOF alignof
#else
#define IDRIS_RT_STATIC_ASSERT _Static_assert
#define IDRIS_RT_ALIGNOF _Alignof
#endif
IDRIS_RT_STATIC_ASSERT(sizeof(void *) == IDRIS_RT_WORD_BYTES &&
                           IDRIS_RT_ALIGNOF(void *) == IDRIS_RT_WORD_BYTES,
                       "an object slot is a pointer of one word");
IDRIS_RT_STATIC_ASSERT(sizeof(idris_rt_header) == IDRIS_RT_WORD_BYTES,
                       "the header is one word, so the object slots after it are aligned");
#undef IDRIS_RT_ALIGNOF
#undef IDRIS_RT_STATIC_ASSERT

#define IDRIS_RT_KIND_BOX 0u
#define IDRIS_RT_KIND_CLOSURE 1u
#define IDRIS_RT_KIND_STRING 2u
#define IDRIS_RT_KIND_BIGNUM 3u
#define IDRIS_RT_KIND_ARRAY 4u
#define IDRIS_RT_STACK_CELL 0x80000000u

#define IDRIS_RT_TAG_LIMIT 0x10000u
#define IDRIS_RT_OBJS_LIMIT 0x100u

/* Constant words are built at compile time in C++ too. */
#ifdef __cplusplus
#define IDRIS_RT_INFO_FUNCTION constexpr
#else
#define IDRIS_RT_INFO_FUNCTION static inline
#endif
IDRIS_RT_INFO_FUNCTION uint32_t idris_rt_info(uint32_t tag, uint32_t objs, uint32_t kind) {
  return tag | objs << 16 | kind << 24;
}
IDRIS_RT_INFO_FUNCTION uint32_t idris_rt_info_tag(uint32_t info) { return info & (IDRIS_RT_TAG_LIMIT - 1u); }
IDRIS_RT_INFO_FUNCTION uint32_t idris_rt_info_objs(uint32_t info) { return info >> 16 & (IDRIS_RT_OBJS_LIMIT - 1u); }
IDRIS_RT_INFO_FUNCTION uint32_t idris_rt_info_kind(uint32_t info) { return info >> 24 & 0x7Fu; }
#undef IDRIS_RT_INFO_FUNCTION

/* A string: the header (kind IDRIS_RT_KIND_STRING, tag 1 only when every
 * byte is ASCII: a slice keeps the flag of the string it is cut from, so an
 * ASCII slice of another string may have 0, and the flag only picks a fast
 * path), the byte length, the number of scalar values, then the UTF-8
 * bytes, in the same allocation. */
typedef struct idris_rt_str {
  idris_rt_header header;
  uint64_t bytes;
  uint64_t scalars;
} idris_rt_str;

/* A big is one 64-bit word. An odd word holds a 63-bit integer
 * shifted left by one; an even word points to an idris_rt_bignum, which holds
 * any integer outside that range. A value is small exactly when it fits, so
 * each integer has one representation. */
typedef int64_t idris_rt_big;

/* A big outside the small range: the header (kind IDRIS_RT_KIND_BIGNUM), the
 * signed number of limbs (GMP's convention: its sign is the integer's, its
 * magnitude the count), then the limbs, least significant first, in the same
 * cell. A big never changes, so its digits live with it, one load from its
 * word, and the cell owns nothing else. The word of a large big is exactly
 * the cell's address, with no tag bit: a prefetcher that follows values
 * shaped like pointers reaches the digits. */
typedef struct idris_rt_bignum {
  idris_rt_header header;
  int64_t size;
} idris_rt_bignum;

/* An array (idr.array.new): the header (kind IDRIS_RT_KIND_ARRAY; its tag
 * is the size of an element in bytes, its objs the number of object slots
 * each element starts with), the number of elements, then the elements, each
 * laid out as idr-lower lays out a cell's fields (object slots first), in the
 * same cell. An element is read and written through the array, in the order
 * of the world, so the array itself is never exclusive: the cell holds its
 * elements' references for as long as it lives. */
typedef struct idris_rt_array {
  idris_rt_header header;
  uint64_t length;
} idris_rt_array;

/* A box is the header (kind IDRIS_RT_KIND_BOX, the constructor's tag), then
 * the constructor's fields, object slots first. A closure is the header (kind
 * IDRIS_RT_KIND_CLOSURE, tag 0), then the code pointer, then the captures,
 * object slots first. Their field layouts are idr-lower's. */

/* Allocation of raw memory, which is not a cell: nothing counts it. The size
 * classes with an allocate and a free entry
 * each: every snmalloc size class from 16 bytes to 1 KiB, with
 * SNMALLOC_MIN_ALLOC_STEP_SIZE=8, so a cell of an 8-byte header
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

/* Reference counting. Every entry point below takes NULL, an odd word and a
 * persistent object too, and then does nothing (idris_rt_is_unique returns
 * false): an object slot may hold any of them, so callers
 * need no test first. */

/* A new cell of `size` bytes, a box or a closure that idr-lower builds (or,
 * with the matching info, anything else the runtime frees): its header is
 * count 1 and `info`, and it counts as a live cell. Exhausted memory ends
 * the process with a crash. In compile-time evaluation's arena the cell is
 * persistent (count 0) instead, and not a live cell. */
void *idris_rt_cell(size_t size, uint32_t info);

/* A new array of `length` elements (a negative length is 0) with the
 * header `info` (kind IDRIS_RT_KIND_ARRAY), counted as idris_rt_cell counts
 * a cell; its elements are not written. Exhausted memory, and a length whose
 * cell would not fit the address space, end the process with a crash. */
idris_rt_array *idris_rt_array_new(int64_t length, uint32_t info);

/* One more owned reference; a count that would reach UINT32_MAX saturates
 * there. */
void idris_rt_inc(void *o);

/* One owned reference less. At 0 the object is released: a box's or a
 * closure's object slots lose a reference each, and then its memory is freed
 * (a stack cell's is not). Objects that reach 0
 * in turn are released the same way, from a worklist that runs through the
 * dying cells themselves: no recursion and no allocation, so freeing takes
 * constant stack however deep the structure is. */
void idris_rt_dec(void *o);

/* Whether o is exclusive: count 1, and not a stack cell. */
bool idris_rt_is_unique(const void *o);

/* Frees the memory of a counted heap cell, and nothing else: the caller has
 * already moved out what it owns, having found it exclusive
 * (idris_rt_is_unique), and reuses the memory of such a cell for one of the
 * same size, rewriting the header, or frees it here. A stack cell's memory
 * is its frame's, so a stack cell is left alone too. */
void idris_rt_free_cell(void *o);

/* The heap cells the runtime allocated (idris_rt_cell, strings and bignums)
 * and has not freed yet, counted by the calling thread: a program is
 * single-threaded, and in idris-mlir-cc each thread that folds counts only
 * its own, with no atomic operation on the allocation path. */
uint64_t idris_rt_live_cells(void);

/* Ownership at the other entry points. A primitive (the string, big, output,
 * show and parse operations below, which the folders call too) borrows its
 * arguments: it neither releases nor keeps them. A primitive that returns an
 * object returns an owned reference: a new object (count 1), a persistent
 * one, or one of its arguments with one more reference. */

/* Standard output and input. They borrow their arguments.
 * Output goes through one static buffer, flushed when it fills, before every
 * read, before a crash's message, and when main returns. */
void idris_rt_flush(void);
/* What @main calls right before it returns: writes pending output, then,
 * when the environment variable IDRIS_RT_LIVE is exactly "1", the line
 * "idris-rt: live cells N\n" (N in decimal, idris_rt_live_cells) to standard
 * error, so a test can check that a program frees every cell it allocates.
 * A crash reports nothing, and neither does compile-time evaluation. */
void idris_rt_main_return(void);
void idris_rt_io_put_str(const idris_rt_str *s);
/* The UTF-8 encoding of the character c: the Prelude's putChar, and what
 * writing a one-character string writes. A Char is a Unicode scalar value,
 * so c is written whole, where both stock backends call C's putchar, as the
 * Prelude declares putChar, and write its low byte (put-char-utf8 in
 * tests/lib/chez-divergences). */
void idris_rt_io_put_char(int32_t c);
/* The decimal text of a signed or an unsigned integer, which idr-lower
 * extends to 64 bits as its type's signedness says. */
void idris_rt_io_put_int_s(int64_t value);
void idris_rt_io_put_int_u(uint64_t value);
/* The text of a double, as idris_rt_str_show_f64 writes it. */
void idris_rt_io_put_double(double value);
/* A string built in place by idr.str.pack and idr.str.concat, which know
 * its size from a first pass: a new string of `bytes` bytes and `scalars`
 * scalar values (`ascii` nonzero when every byte is ASCII), whose bytes
 * the caller then writes in order, a character's UTF-8 or a string's
 * bytes at an offset, each giving the next offset. The empty string is
 * shared and never written. */
idris_rt_str *idris_rt_str_alloc(int64_t bytes, int64_t scalars, int32_t ascii);
int64_t idris_rt_str_put_char(idris_rt_str *s, int64_t offset, int32_t c);
int64_t idris_rt_str_put_str(idris_rt_str *s, int64_t offset, const idris_rt_str *part);
/* The byte length of a string, and whether every byte is ASCII. */
int64_t idris_rt_str_bytes_length(const idris_rt_str *s);
int32_t idris_rt_str_is_ascii(const idris_rt_str *s);
/* One byte, or 255 at the end of input. */
int32_t idris_rt_io_get_byte(void);
/* A line of input without its end, the Prelude's getLine: the bytes up to
 * the next '\n', which is consumed, without that '\n' or the "\r\n" it
 * ends; the rest of the input when no '\n' is left, and the empty string at
 * the end of input. The bytes are decoded as idris_rt_str_from_bytes
 * decodes them. A new string. */
const idris_rt_str *idris_rt_io_get_line(void);
/* Bytes [offset, offset + count) of a byte array to a standard stream:
 * handle 1 is standard output, through the output buffer and in order with
 * every other write to it; 2 is standard error; any other handle writes
 * nothing and gives 0. A range outside the array's `length` bytes is a
 * crash. Gives the count written. */
int64_t idris_rt_io_write_bytes(int64_t handle, idris_rt_array *bytes, int64_t length,
                                int64_t offset, int64_t count);
/* Bytes from a standard stream into [offset, offset + count) of a byte
 * array: handle 0 is standard input, giving the count read, 0 at the end of
 * input; any other handle reads nothing and gives 0. A range outside the
 * array is a crash. */
int64_t idris_rt_io_read_bytes(int64_t handle, idris_rt_array *bytes, int64_t length,
                               int64_t offset, int64_t count);
/* 1 once a read on the handle met the end of input, as C's feof reports it,
 * else 0; only handle 0 is read. */
int64_t idris_rt_io_eof(int64_t handle);
/* Writes pending output, then the len bytes of msg to standard error, then
 * ends the process with status IDRIS_RT_CRASHED. */
IDRIS_RT_NORETURN void idris_rt_crash(const char *msg, size_t len);

/* The exit status of a program that the runtime ends with a message on
 * standard error ("idris-mlir: <cause>"): a crash, the stack running out, a
 * CPU without the features the program was compiled to use. */
#define IDRIS_RT_CRASHED 1

/* The program's entry, which @main calls with the program and the
 * IDRIS_RT_CPU_FEATURES bits its target enables (cpu_features.h). When the
 * CPU lacks one of them, it names them and ends the process with
 * IDRIS_RT_CRASHED before the program runs; it is compiled for the target's baseline, and idris-mlir-cc
 * keeps it there. Otherwise it runs body on a reserved stack
 * (idris_rt_run_on_stack) of the number of bytes the environment variable
 * IDRIS_RT_STACK says, or else of a gibibyte, or of the stack limit when
 * that is larger; when that stack runs out, the output written so far is flushed,
 * "idris-mlir: stack exhausted" is written to standard error, and the
 * process ends with IDRIS_RT_CRASHED. What body returns is the exit status:
 * it returns a status from 0 to 255, and ends the process as a crash that
 * names any other value, which no parent could tell from its low 8 bits. */
int32_t idris_rt_start(int64_t (*body)(void), uint64_t cpu);

/* The reserved-stack runner, which programs, idris-mlir-cc and compile-time
 * evaluation's child share: runs fn(arg) on a new thread whose stack is
 * reserved address space, committed as it is touched, of the largest size
 * from `most` bytes down by halves to 64 MiB (or `most`, when smaller)
 * that the machine grants, with `guard` inaccessible bytes below it. A fault on the guard is the stack
 * running out: exhausted() runs, on a signal stack of its own, and must end
 * the process with only async-signal-safe calls. Any other fault gets the
 * action it had before. One runner runs at a time in a process. Returns 0
 * once fn has returned, or -1 when no stack could be reserved. */
int idris_rt_run_on_stack(void (*fn)(void *), void *arg, size_t most, size_t guard,
                          void (*exhausted)(void));

/* Doubles. x truncated toward zero, modulo 2^64; x is
 * finite (idr-lower checks it first). */
int64_t idris_rt_to_int(double x);
/* The first character of the text of a double (idris_rt_str_show_f64):
 * '-', a digit, or the 'i' of inf or the 'n' of nan. */
int32_t idris_rt_double_head(double x);
/* The first character of the decimal text of a signed or unsigned integer. */
int32_t idris_rt_int_head_s(int64_t value);
int32_t idris_rt_int_head_u(uint64_t value);

/* Strings. Strings are immutable; each operation borrows its arguments and
 * returns an owned string: a new one, a persistent one (the empty string), or
 * an argument with one more reference (appending the empty string, reversing
 * an empty one). Preconditions, which idr-lower
 * checks and crashes on before the call: idris_rt_str_index needs
 * 0 <= i < length, idris_rt_str_head and idris_rt_str_tail a nonempty
 * string. */
const idris_rt_str *idris_rt_str_append(const idris_rt_str *a, const idris_rt_str *b);
const idris_rt_str *idris_rt_str_cons(int32_t c, const idris_rt_str *s);
const idris_rt_str *idris_rt_str_from_char(int32_t c);
const idris_rt_str *idris_rt_str_show_s(int64_t value);
const idris_rt_str *idris_rt_str_show_u(uint64_t value);
/* The text of a double, which reads back as it (idris_rt_str_to_double): the
 * fewest significant digits that do, the nearest of those to the double, and
 * of two equally near the one whose last digit is even; positional from 1e-3
 * up to 1e10, with a digit after the point (0.001, 100.0), else in
 * scientific notation (1e21, 1.5e-7, 5e-324); inf, -inf and nan, a NaN
 * whatever its sign; -0.0 with its sign. */
const idris_rt_str *idris_rt_str_show_f64(double value);
/* The number of scalar values. */
int64_t idris_rt_str_length(const idris_rt_str *s);
int32_t idris_rt_str_index(const idris_rt_str *s, int64_t i);
int32_t idris_rt_str_head(const idris_rt_str *s);
const idris_rt_str *idris_rt_str_tail(const idris_rt_str *s);
/* The Prelude's substr: the scalars from `start`, at most `len` of them; ""
 * when the start is past the end, and only those left when fewer than `len`
 * are. A negative start or length, which only a call of the primitive itself
 * passes, counts as 0. */
const idris_rt_str *idris_rt_str_substr(const idris_rt_str *s, int64_t start, int64_t len);
const idris_rt_str *idris_rt_str_reverse(const idris_rt_str *s);
/* Negative, zero or positive as a is before, equal to or after b in the
 * order of their scalar values, Unicode's code point order, which is the
 * byte order of their UTF-8. */
int32_t idris_rt_str_cmp(const idris_rt_str *a, const idris_rt_str *b);
/* `cast` from String: the whole string is an optional sign (`+` or `-`)
 * and a literal of the target type as Idris writes it; any other string
 * is 0.
 * - to an integer: an integer literal, decimal digits or 0b, 0o, 0x or 0X
 *   and digits of that base, single underscores between digits allowed,
 *   gives that integer, exactly;
 * - to Double: an integer literal, digits, a point and digits with an
 *   optional exponent (`e`, an optional sign, digits), or digits and an
 *   exponent, give the nearest double, ties to even (so every text
 *   idris_rt_str_show_f64 writes reads back as its double), an exponent
 *   out of range an infinity or a zero; `inf`, `infinity` and `nan`, in any
 *   case, give an infinity and NaN.
 * idris_rt_str_to_int returns the result modulo 2^64; idr-lower wraps it to
 * the op's width. */
double idris_rt_str_to_double(const idris_rt_str *s);
int64_t idris_rt_str_to_int(const idris_rt_str *s);
/* The string of n bytes of well-formed UTF-8 at p: a new string, or the
 * persistent empty one. */
const idris_rt_str *idris_rt_str_from_utf8(const char *p, size_t n);
/* The string of any n bytes at p, decoded as UTF-8: how bytes from outside
 * the program become a string. Well-formed sequences are their scalars, and
 * each maximal subpart of an ill-formed one, the longest prefix of a
 * well-formed sequence at that point or else one byte, is one U+FFFD, as the
 * Unicode Standard recommends (chapter 3). A new string, or the persistent
 * empty one. */
const idris_rt_str *idris_rt_str_from_bytes(const char *p, size_t n);
/* The UTF-8 bytes of s, valid as long as s is. */
const char *idris_rt_str_bytes(const idris_rt_str *s);

/* Bigs: Integer, and the Nat-like types. Each operation borrows its
 * arguments and returns an owned result: a small word, or a new bignum.
 * Division and modulus are Euclidean, the remainder in [0, |b|), and the
 * bitwise operations are those of the infinite two's complement
 * representation, as upstream Idris's test suite requires of every backend
 * (its integers test of Chez, RefC and Node); the divisor is nonzero
 * (idr-lower checks it first). */
idris_rt_big idris_rt_big_add(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_sub(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_mul(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_div(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_mod(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_and(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_or(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_xor(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_neg(idris_rt_big a);
/* a - 1, for a natural that is not zero (idr.big.pred). */
idris_rt_big idris_rt_big_pred(idris_rt_big a);
/* An Integer as a natural: 0 if it is negative, else itself
 * (idr.nat.from_big, Idris's integerToNat). */
idris_rt_big idris_rt_nat_from_big(idris_rt_big a);
/* Negative, zero or positive as a < b, a = b or a > b. */
int32_t idris_rt_big_cmp(idris_rt_big a, idris_rt_big b);
idris_rt_big idris_rt_big_from_int_s(int64_t value);
idris_rt_big idris_rt_big_from_int_u(uint64_t value);
/* The value modulo 2^64; idr-lower wraps it to the op's width. */
int64_t idris_rt_big_to_int(idris_rt_big a);
/* x truncated toward zero; x is finite (idr-lower checks it first). */
idris_rt_big idris_rt_big_from_double(double x);
/* The double nearest to a, ties to even, an infinity past the largest: the
 * conversion of IEEE 754 under its default rounding. */
double idris_rt_big_to_double(idris_rt_big a);
/* A new string. */
const idris_rt_str *idris_rt_big_show(idris_rt_big a);
/* The integer cast of idris_rt_str_to_int, without the wrapping. */
idris_rt_big idris_rt_big_from_str(const idris_rt_str *s);

/* Dropping the reference an operation returned, for callers that own it and
 * hold a string or a big rather than a pointer: the compiler's folders, which
 * turn each result into an attribute. Both are idris_rt_dec. */
void idris_rt_str_release(const idris_rt_str *s);
void idris_rt_big_release(idris_rt_big a);

/* Strings over simdutf. */
/* The number of scalar values in n bytes of well-formed UTF-8. */
size_t idris_rt_utf8_count(const char *p, size_t n);
/* Whether the n bytes at p are all ASCII. */
bool idris_rt_ascii(const char *p, size_t n);

/* `cast` from String to Double over the n bytes at p (idris_rt_str_to_double). */
double idris_rt_parse_double(const char *p, size_t n);

/* Points GMP's memory functions at the runtime's allocator. The
 * big operations call it themselves before GMP first allocates. */
void idris_rt_gmp_init(void);

/* Compile-time evaluation. idr-eval runs the calls of a
 * round in a child process, whose JITed code idr-lower wrote in JIT mode:
 * cells come from idris_rt_arena_alloc and a crash is idris_rt_eval_crash.
 * idris_rt_eval_begin, called once in the child, makes every other
 * allocation of the runtime use the arena too, and every cell the runtime
 * makes there (idris_rt_cell, strings, bignums) persistent: count 0, not a
 * live cell, so counting does nothing in the child. A cell JIT-mode code
 * takes from idris_rt_arena_alloc itself must be written with count 0 too.
 * The arena is never freed: the child ends with the round, and memory
 * management is not observable. Only the compiler calls these, natively,
 * never a program (eval.cc annotates them so); the runtime idris-mlir-cc
 * prepares for programs has no entry for them. */
void idris_rt_eval_begin(int report_fd);
void *idris_rt_arena_alloc(size_t size);
/* Writes msg to the report descriptor, then ends the child with
 * IDRIS_RT_EVAL_CRASHED. */
IDRIS_RT_NORETURN void idris_rt_eval_crash(const char *msg, size_t len);

/* A call of code Idris does not prove terminating runs metered: from
 * idris_rt_eval_meter until idris_rt_eval_unmetered, it may take `ticks`
 * ticks, allocate `bytes` bytes of arena and use `stack` bytes of stack
 * below the caller of idris_rt_eval_meter, or the child ends with
 * IDRIS_RT_EVAL_OVER_BUDGET. idris_rt_eval_tick, which JIT-mode code calls
 * where such code may loop or recurse, counts a tick and checks the stack;
 * unmetered it does nothing. */
void idris_rt_eval_meter(uint64_t ticks, uint64_t bytes, uint64_t stack);
void idris_rt_eval_unmetered(void);
void idris_rt_eval_tick(void);

/* The exit statuses of an evaluation child: its calls crashed, the
 * machine refused memory, or a metered call spent its budget. */
#define IDRIS_RT_EVAL_CRASHED 3
#define IDRIS_RT_EVAL_EXHAUSTED 4
#define IDRIS_RT_EVAL_OVER_BUDGET 6

#ifdef __cplusplus
}
#endif

#endif /* IDRIS_RT_H */
