// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The runtime's C interface: the layouts lowered code and the runtime
 * share, which idr-lower writes constants of into static data; the ownership
 * rules every entry point keeps; the ABI's constants; and the prototypes of
 * the functions lowered code does not call. idris_rt_ops.h, generated from
 * the dialect's ODS, declares every function idr-lower calls. A function's
 * meaning is documented beside its definition, in runtime/.
 *
 * Every function the runtime exports is named by a C identifier, with no
 * `$`: each name the compiler reserves for a symbol of its own has a `$`
 * followed by a letter, so none of them is a runtime function's.
 *
 * A program inlines the runtime's bitcode where that pays and links the rest
 * natively, so what a program does not call is not in its executable.
 * idris-mlir links the same code natively: the folders of the string and big
 * ops call it, so a primitive has one implementation at compile time and at
 * runtime. */
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
 * - 0: persistent. Static data is never counted and never freed. Everything a
 *   persistent object points to is persistent: a static memo cell (kind
 *   IDRIS_RT_KIND_THUNK), which its first force writes once, makes the value
 *   it then holds persistent (idris_rt_persist_held), every counted cell it
 *   reaches getting count 0, live until the program ends.
 * - 1 to UINT32_MAX - 1: owned references, counted with plain arithmetic,
 *   since a program is single-threaded.
 * - UINT32_MAX: saturated. A count that would overflow stops there, and the
 *   object is never decremented or freed: an overflow leaks the object
 *   instead of freeing it while it is still in use.
 *
 * info is tag | objs << 16 | kind << 24, with bit 31 marking a stack cell.
 * Freeing reads only objs (and the word that counts a wide cell's slots),
 * kind and bit 31, and an array's tag and length when its elements hold
 * objects, so the runtime frees any cell without knowing its type.
 * - tag (bits 0-15): a box's constructor tag, a thunk's state (the
 *   constructor of its memo sum it holds), an array's element size in
 *   bytes; 0 for a string and a bignum.
 * - objs (bits 16-23): the number of object slots, one word
 *   (IDRIS_RT_WORD_BYTES) each. A box's and a thunk's are the first objs
 *   slots right after the header, unless objs is IDRIS_RT_OBJS_WIDE: then
 *   the word right after the header (a uint64_t) is their number, and they
 *   come right after that word. Strings and bignums have none. An array's
 *   are per element: its first objs words (idris_rt_array), fewer than
 *   IDRIS_RT_OBJS_WIDE, since an element with more is held boxed.
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
 * have them: every target, Linux and macOS, x86_64 and arm64, is LP64. */
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
/* A thunk cell is laid out as a box: tag, objs and object slots first. The
 * tag says which state it is in, and freeing reads it as it reads a box.
 * Only the kind tells a memo cell, which may be written, from a box, which
 * may not. */
#define IDRIS_RT_KIND_THUNK 1u
#define IDRIS_RT_KIND_STRING 2u
#define IDRIS_RT_KIND_BIGNUM 3u
#define IDRIS_RT_KIND_ARRAY 4u
#define IDRIS_RT_STACK_CELL 0x80000000u

#define IDRIS_RT_TAG_LIMIT 0x10000u
#define IDRIS_RT_OBJS_LIMIT 0x100u
/* The objs of a box or a thunk with too many object slots for the field to
 * count, which a word after the header counts instead. */
#define IDRIS_RT_OBJS_WIDE (IDRIS_RT_OBJS_LIMIT - 1u)

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

/* A string: the header (kind IDRIS_RT_KIND_STRING, tag 0), the byte
 * length, the number of scalar values, then the UTF-8 bytes, in the same
 * allocation. Every scalar takes at least one byte and only an ASCII one
 * takes exactly one, so a string is ASCII exactly when its two lengths are
 * equal: no flag says it again. */
typedef struct idris_rt_str {
  idris_rt_header header;
  uint64_t bytes;
  uint64_t scalars;
} idris_rt_str;

/* The UTF-8 bytes of s, right after its lengths, valid as long as s is.
 * Inline, since every string operation reads them. */
#ifdef __cplusplus
inline const char *idris_rt_str_bytes(const idris_rt_str *s) {
  return reinterpret_cast<const char *>(s + 1);
}
#else
static inline const char *idris_rt_str_bytes(const idris_rt_str *s) {
  return (const char *)(s + 1);
}
#endif

/* A big is one 64-bit word. An odd word holds a 63-bit integer
 * shifted left by one; an even word points to an idris_rt_bignum, which holds
 * any integer outside that range. A value is small exactly when it fits, so
 * each integer has one representation. */
typedef int64_t idris_rt_big;

/* The small range, the integers an odd word holds: 63 bits of two's
 * complement, from -2^62 to 2^62 - 1. The runtime's bigs and the compiler's
 * ranges read these two, so the bound a value is narrowed by is the one the
 * runtime holds it small by. */
#define IDRIS_RT_SMALL_MIN (-(INT64_C(1) << 62))
#define IDRIS_RT_SMALL_MAX ((INT64_C(1) << 62) - 1)

/* Whether a word is small, by its low bit, and the value a small one holds:
 * a small value's word is 2v + 1 (idris_rt_small_word, the function of
 * idr.big.small), and a large big's is even. */
#ifdef __cplusplus
constexpr bool idris_rt_word_is_small(idris_rt_big word) { return (word & 1) != 0; }
constexpr int64_t idris_rt_small_value(idris_rt_big word) { return word >> 1; }
#else
static inline bool idris_rt_word_is_small(idris_rt_big word) { return (word & 1) != 0; }
static inline int64_t idris_rt_small_value(idris_rt_big word) { return word >> 1; }
#endif

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

/* An array cell, the memory behind every memref: the header (kind
 * IDRIS_RT_KIND_ARRAY; its tag is the size of an element in bytes, its objs
 * the number of object slots each element starts with), the number of
 * elements the cell holds, then the elements, each laid out as idr-lower
 * lays out a cell's fields (object slots first). An IORef is a cell of one
 * element.
 *
 * The length is the cell's own: written once, when the cell is made, and read
 * only by the runtime, to release each element's object slots when a counted
 * cell dies. The shape of a memref is its descriptor's (idris_rt_memref),
 * which may view part of a cell, and compiled code never reads the length.
 * Every object slot of every element holds NULL, an odd word or a counted
 * reference for as long as the cell lives: a store into an element releases
 * what the slot held, and so does the cell's death.
 *
 * A constant array is one static cell laid out as every other: a persistent
 * header (count 0), its length the number of elements, then its data. Its
 * elements hold no object. No entry point writes a header whose count is 0,
 * so the whole cell may be read-only. */
typedef struct idris_rt_array {
  idris_rt_header header;
  uint64_t length;
} idris_rt_array;

/* The bytes of a byte array (a Data.Buffer), right after its length. A byte
 * array passes as its cell; every span an entry point reads or writes lies in
 * it, idr.check.range having tested it before the call, and an address in it
 * need not be aligned. */
#ifdef __cplusplus
inline char *idris_rt_array_bytes(idris_rt_array *cell) {
  return reinterpret_cast<char *>(cell + 1);
}
#else
static inline char *idris_rt_array_bytes(idris_rt_array *cell) { return (char *)(cell + 1); }
#endif

/* A memref's descriptor, as LLVM lays one out for a memref of rank R: the
 * allocated pointer, the cell; the aligned pointer, always the cell's first
 * element, right after its header; the offset of the view's first element
 * from the aligned pointer; then R sizes and R strides, int64_t each, right
 * after these three words. The offset, the sizes and the strides count
 * elements. */
typedef struct idris_rt_memref {
  idris_rt_array *allocated;
  char *aligned;
  int64_t offset;
} idris_rt_memref;

/* A box is the header (kind IDRIS_RT_KIND_BOX, the constructor's tag), then
 * the constructor's fields, object slots first (after their number, when
 * there are IDRIS_RT_OBJS_WIDE or more). A thunk is the same with kind
 * IDRIS_RT_KIND_THUNK: the tag of the state it is in, then that state's
 * fields, in a cell as large as its largest state. A cell holds no code
 * address. Their field layouts are idr-lower's. */

/* The functions idr-lower calls, the ops' (their Idr_Runtime) and the cell,
 * array, counting, string-building, crash and entry functions, declared from
 * the dialect's ODS, so that a definition in runtime/ that does not take what
 * lowered code passes and give what it expects fails to compile. */
#include "idris_rt_ops.h"

/* Reference counting's entry points take NULL, an odd word and a persistent
 * object too, and then do nothing, but for its test of exclusivity, which
 * takes a cell: an object slot may hold any of them, so callers need no test
 * first.
 *
 * Ownership at the other entry points. A primitive (the string, big, output,
 * show and parse operations, which the folders call too) borrows its
 * arguments: it neither releases nor keeps them. A primitive that returns an
 * object returns an owned reference: a new object (count 1), a persistent
 * one, or one of its arguments with one more reference.
 *
 * Strings are immutable; each operation borrows its arguments and returns an
 * owned string: a new one, a persistent one (the empty string), or an
 * argument with one more reference (appending the empty string, reversing an
 * empty one).
 *
 * Bigs: Integer, and the Nat-like types. Each operation borrows its
 * arguments and returns an owned result: a small word, or a new bignum.
 *
 * Base's files, directories, process, terminal, errors and clocks
 * (System.File, System.Directory, System, System.Term, System.Errno,
 * System.Clock) borrow their arguments, and a string they return is new. */

/* A pointer of base is a handle, an int64_t: -1 is null; 0, 1 and 2 are
 * standard input, output and error, slots of the handle table made with it
 * and never freed; any other is a slot the program opened. A string handle
 * read from a file or naming the current directory is the program's, which
 * frees it; one of the environment or of a directory's entries is the
 * runtime's, as getenv's and readdir's bytes are the C library's: the next
 * call of its kind, or closing its directory, releases it, and freeing its
 * handle does nothing.
 *
 * An OSClock is seconds << 30 | nanoseconds, or -1 when it is not valid.
 *
 * A failing call sets the runtime's saved errno, which base's errno and
 * file errors read. */

/* The exit status of a program the runtime ends with a message on standard
 * error, `idris-mlir: `, the cause idris_rt_crash is given, and a newline: a
 * crash, the stack running out, a processor without the features the
 * program was compiled to use, a system whose page size is not the one the
 * runtime is built for. */
#define IDRIS_RT_CRASHED 1

/* The mark of what runs before the processor test (the page-size check, the
 * test, and what they write and how they end the process): idris-mlir finds
 * a function annotated with it by this name, and keeps it compiled for the
 * target's baseline, where it raises every other to the program's CPU. */
#define IDRIS_RT_BASELINE_MARK "idris-rt-baseline"
#define IDRIS_RT_BASELINE __attribute__((annotate(IDRIS_RT_BASELINE_MARK)))

/* The functions lowered code does not call: idris-mlir calls them natively
 * (its folders, its tools, idr-lower's static data), and so do the runtime's
 * tests. */
uint64_t idris_rt_live_cells(void);
void idris_rt_flush(void);
int idris_rt_run_on_stack(void (*fn)(void *), void *arg, void (*exhausted)(void));
const idris_rt_str *idris_rt_str_from_utf8(const char *p, size_t n);
const idris_rt_str *idris_rt_str_from_bytes(const char *p, size_t n);
void idris_rt_str_release(const idris_rt_str *s);
void idris_rt_big_release(idris_rt_big a);
size_t idris_rt_utf8_count(const char *p, size_t n);
void idris_rt_gmp_init(void);

#ifdef __cplusplus
}
#endif

#endif /* IDRIS_RT_H */
