// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The runtime's C interface: the layouts lowered code and the runtime
 * share, which idr-lower writes constants of into static data; the ownership
 * rules every entry point keeps; the ABI's constants; and the prototypes of
 * the functions lowered code does not call. idris_rt_ops.h, generated from
 * the dialect's specification, declares every function idr-lower calls. A function's
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
 * - 0: not counted. Static data, and every cell of a lexical lifetime
 *   (freed with its lifetime, never by a count), are never counted and never
 *   freed by one; static data may be read-only.
 * - 1 to UINT32_MAX - 1: owned references, counted with plain arithmetic,
 *   since a program is single-threaded. 1 is the one reference: a cell of
 *   count 1 is exclusive.
 * - UINT32_MAX: saturated. A count that would overflow stops there, and the
 *   object is never decremented or freed: an overflow leaks the object
 *   instead of freeing it while it is still in use.
 * Both marks are one unsigned comparison away from a counted value, so the
 * test that keeps a saturated count saturated is the one that leaves static
 * data alone, and costs nothing more.
 *
 * info is tag | objs << 16 | kind << 24. Freeing reads only objs (and the
 * word that counts a wide cell's slots) and kind, and an array's tag and
 * length when its elements hold objects, so the runtime frees any cell
 * without knowing its type.
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
 * - kind (bits 24-31): one of the IDRIS_RT_KIND_ values.
 * idris_rt_info builds the word, and the accessors below take it apart. It
 * does not check its arguments: idr-lower builds every word it writes
 * through its CellInfo, which exists only for a tag below IDRIS_RT_TAG_LIMIT
 * and an object count below IDRIS_RT_OBJS_LIMIT, so that no field of a word
 * the compiler writes overflows into the next.
 *
 * An object slot holds a counted reference: a pointer to an object, NULL (an
 * unused pointer slot of an unboxed sum), or an odd word (a small Integer or
 * Nat, as idris_rt_big has them). Which of those a slot may hold is its
 * type's, and the counting entry the lowering calls for it is that kind's.
 * A cell's other fields come after its object slots, so the slots are all
 * the runtime needs to find. */
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
IDRIS_RT_INFO_FUNCTION uint32_t idris_rt_info_kind(uint32_t info) { return info >> 24; }
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
 * The cell's maker writes every element whole before anything reads,
 * releases or frees it; from then on every object slot of every element
 * holds NULL, an odd word or a counted reference for as long as the cell
 * lives: a store into an element releases what the slot held, and so does
 * the cell's death.
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

/* A text of the program's static data, which the runtime only writes out:
 * a source file's name or a function's in a crash site, shared by every site
 * that names it. Its length, then its bytes, with no padding between, since
 * bytes need none: the constant idr-lower writes is { i32, [length x i8] }.
 * C++ has no flexible array member to name the bytes, so they are read past
 * the struct (idris_rt_text_bytes), as a string's and an array's are. */
typedef struct idris_rt_text {
  uint32_t length;
} idris_rt_text;

#ifdef __cplusplus
inline const char *idris_rt_text_bytes(const idris_rt_text *text) {
  return reinterpret_cast<const char *>(text + 1);
}
#else
static inline const char *idris_rt_text_bytes(const idris_rt_text *text) {
  return (const char *)(text + 1);
}
#endif

/* What the lowering knows of the program, one constant @main passes to
 * idris_rt_start: the body, the IO root, which takes and gives nothing; and
 * the IDRIS_RT_CPU_FEATURES bits (cpu_features.h) of the features its target
 * enables, which the processor must have. */
typedef struct idris_rt_program {
  void (*body)(void);
  uint64_t cpu_features;
} idris_rt_program;

/* What only the driver knows of the program, once code generation has given
 * each function's frame: one constant of an object the driver compiles after
 * the program's, which every executable links. The bytes of the deepest path
 * of calls the program's code can make, every frame on it its own size as
 * code generation laid it out, the runtime's frames included; the largest
 * single frame, which the guard below the stack is at least, so no frame can
 * step over it; the bytes of the deepest path the fault handler's code can
 * take on the signal stack; and the program's name, the executable's as the
 * driver built it, which every message begins with. Calls into code outside
 * the program (the C library, GMP) are the runtime's margin for it, a fact of
 * the target's entry. */
typedef struct idris_rt_built {
  uint64_t stack_bytes;
  uint64_t frame_bytes;
  uint64_t signal_bytes;
  const char *name;
  uint64_t name_bytes;
} idris_rt_built;

extern const idris_rt_built idris_rt_program_built;
/* Its name, which the driver defines it by. */
#define IDRIS_RT_PROGRAM_BUILT_NAME "idris_rt_program_built"

/* A lifetime the program allocates into by a bump: a chain of chunks, and a
 * cursor, the first free byte of its newest chunk, which compiled code
 * threads from one cell to the next: idris_rt_arena_chunk gives where a cell
 * goes, and the next cursor is that plus the cell's bytes, a multiple of the
 * word. Its cells carry no count (their headers' count is 0) and die with
 * it: closing the chain gives every chunk back (idris_rt_arena_close), and a
 * stack lifetime's end gives back the chunks taken since its mark, the
 * cursor when it opened (idris_rt_stack_reset).
 *
 * The thread's frame stack, where a recursion on a cycle of calls keeps its
 * depth: frames contiguous within chunks, each pushed once
 * (idris_rt_frame_push) and popped by putting the stack back to it
 * (idris_rt_frame_pop), which gives back the chunks past it and keeps one
 * as the spare, so a push and a pop alternating at a chunk's edge call the
 * allocator at most once. */

/* The functions idr-lower calls, the ops' runtime functions and the helpers
 * no op names (the cell, array, counting, token, string-building, crash,
 * lifetime, frame-stack, account and entry functions), declared from the
 * dialect's specification, each pointer with the C type it points to, so
 * that a definition in runtime/ that does not take what lowered code passes
 * and give what it expects fails to compile. */
#include "idris_rt_ops.h"

/* Counting has one increment and one decrement for each kind of word a
 * counted reference may be: a cell, a cell or NULL, a cell or a small value,
 * or any of the three. The lowering calls the one its type says, so each
 * tests exactly what the kind leaves open and nothing it rules out; a static
 * or saturated count is left as it is (count 0 and UINT32_MAX, above). A
 * reuse token's memory is freed with no test of its count: one proved
 * exclusive with no test at all, one that may be null testing that alone.
 *
 * Ownership at the other entry points. A primitive (the string, big, output,
 * show and parse operations, which the folders call too) borrows its
 * arguments: it neither releases nor keeps them. A primitive that returns an
 * object returns an owned reference, fresh: a new object (count 1) or a
 * static one, never one of its arguments, even where its value is one (an
 * empty string appended, a shift of no places), so its result's identity is
 * its own. The Nat of an Integer alone gives back a large argument that is
 * not negative, with one more reference: it writes a count.
 *
 * Strings are immutable; each operation borrows its arguments and returns an
 * owned string: a new one, or a static one (the empty string).
 *
 * Bigs: Integer, and the Nat-like types. Each operation borrows its
 * arguments and returns an owned result: a small word, or a new bignum.
 *
 * Base's files, directories, process, terminal, errors and clocks
 * (System.File, System.Directory, System, System.Term, System.Errno,
 * System.Clock) borrow their arguments, and a string they return is new. */

/* A pointer of base is a handle, an int64_t: null, every bit set, which
 * numbers no slot; standard input, output and error, the first slots of the
 * handle table, made with it and never freed; or a slot the program opened.
 * The specification gives null's handle and the streams' (idr::handles). A
 * string handle read from a file or naming the current directory is the
 * program's, which frees it; one of the environment or of a directory's
 * entries is the runtime's, as getenv's and readdir's bytes are the C
 * library's: the next call of its kind, or closing its directory, releases
 * it, and freeing its handle does nothing.
 *
 * An OSClock is a reading, its seconds shifted past its nanoseconds, or the
 * mark of a clock that could not be read, as the specification encodes them
 * (idr::clocks).
 *
 * A failing call sets the runtime's saved errno, which base's errno and
 * file errors read. */

/* The mark of what runs before the processor test (the page-size check, the
 * test, and what they write and how they end the process): idris-mlir finds
 * a function annotated with it by this name, and keeps it compiled for the
 * target's baseline, where every other takes the program's CPU. */
#define IDRIS_RT_BASELINE_MARK "idris-rt-baseline"
#define IDRIS_RT_BASELINE __attribute__((annotate(IDRIS_RT_BASELINE_MARK)))

/* The mark of the function the kernel calls on a fault, on the signal
 * stack: idris-mlir finds it by this name and sizes the signal stack by the
 * deepest path of calls from it, as it sizes the stack by the program's. */
#define IDRIS_RT_HANDLER_MARK "idris-rt-handler"
#define IDRIS_RT_HANDLER __attribute__((annotate(IDRIS_RT_HANDLER_MARK)))

/* What a reserved stack is to hold, for the runner: the bytes of the deepest
 * path of calls the code run on it can make, its largest frame, which the
 * guard below it is at least, and the bytes the fault handler's path takes on
 * the signal stack. The runner adds to both stacks what outside code takes
 * (the target's one margin) and what the host's own thread and signal
 * delivery take, which it reads at start, and rounds each to pages. */
typedef struct idris_rt_stack_plan {
  uint64_t stack_bytes;
  uint64_t frame_bytes;
  uint64_t signal_bytes;
} idris_rt_stack_plan;

/* How a run on a reserved stack went: the function ran and returned, or the
 * system refused the memory the runner asked for (its stacks, the heap's
 * page map), which is the process running out of memory. */
typedef enum idris_rt_ran { IDRIS_RT_RAN, IDRIS_RT_REFUSED } idris_rt_ran;

/* The functions lowered code does not call: idris-mlir calls them natively
 * (its folders, its tools, idr-lower's static data), and so do the runtime's
 * tests. The tools run on idris_rt_run_on_stack, as a program runs on
 * idris_rt_start's runner: it passes the same startup check (the page, and
 * the IDRIS_RT_CPU_FEATURES bits of the program CPU's features, which the
 * runtime's native code a tool links needs), then sets up the heap and GMP's
 * allocation once, before anything else of the runtime runs, so every other
 * function here is called from inside fn. A tool's own allocator that runs
 * out ends the process through idris_rt_out_of_memory, as lowered code
 * does. */
idris_rt_ran idris_rt_run_on_stack(void (*fn)(void *), void *arg, const idris_rt_stack_plan *plan,
                                   const char *name, size_t name_bytes);
/* The bytes of the stack the runner gave fn's thread, the plan's with the
 * host's own part, in pages: a tool gives each of its threads as many. */
uint64_t idris_rt_thread_stack_bytes(void);
/* Run first on each other thread a tool starts, on it: a signal stack as
 * fn's thread has, and its stack's guard known to the fault handler, so
 * reaching it is the tool's internal error; given back as the thread ends. */
void idris_rt_start_thread(void);
/* The memory a tool may plan for: physical memory, capped by the process's
 * address-space limit and by what its cgroup lets it still commit. */
uint64_t idris_rt_host_memory(void);
/* What a process may still commit before its host kills it, as a Linux
 * host's cgroup files under root state it: "" for this host's own, or a
 * directory where a test planted a host's proc/self/cgroup,
 * proc/self/mountinfo, proc/meminfo and the cgroup hierarchy they name;
 * UINT64_MAX where no limit holds. The same reader on every target. */
uint64_t idris_rt_commit_limit(const char *root);
void idris_rt_flush(void);
const idris_rt_str *idris_rt_str_from_utf8(const char *p, size_t n);
const idris_rt_str *idris_rt_str_from_bytes(const char *p, size_t n);
size_t idris_rt_utf8_count(const char *p, size_t n);

#ifdef __cplusplus
}
#endif

#endif /* IDRIS_RT_H */
