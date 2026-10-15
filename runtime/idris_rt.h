// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The runtime's C interface.
 *
 * Every helper that idr-lower calls is here. A program inlines the
 * runtime's bitcode where that pays and links the rest natively, so what a
 * program does not call is not in its executable. idris-mlir links the
 * same code natively: the folders of the string and big ops call it, so a
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

/* Every heap object starts with this header.
 *
 * count is how many owned references the object has, or one of two marks:
 * - 0: persistent. Static data is never counted and never freed. Everything a
 *   persistent object points to is persistent, except a static memo cell
 *   (kind IDRIS_RT_KIND_THUNK), which its first force writes once and whose
 *   forced value is counted and released by idris_rt_caf_release.
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
 *   constructor of its memo sum it holds), a string's ASCII flag in bit 0
 *   (set only when every byte is ASCII), an array's element size in bytes;
 *   0 for a bignum.
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

/* The functions each op that calls the runtime names (its Idr_Runtime),
 * declared from the dialect's ODS, so that a definition here that does not
 * take its op's operands and give its op's result fails to compile. Each
 * one's meaning is documented below with the runtime's other functions. */
#include "idris_rt_ops.h"

/* Allocation of raw memory, which is not a cell: nothing counts it. The size
 * classes with an allocate and a free entry
 * each: every snmalloc size class from 16 bytes to 1 KiB, with
 * SNMALLOC_MIN_ALLOC_STEP_SIZE=8, so a cell of an 8-byte header
 * and two fields takes exactly 24 bytes. rt.alloc checks that each is
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

/* A new cell of `size` bytes, a box or a thunk that idr-lower builds (or,
 * with the matching info, anything else the runtime frees): its header is
 * count 1 and `info`, and it counts as a live cell. Exhausted memory ends
 * the process with a crash. */
void *idris_rt_cell(size_t size, uint32_t info);

/* A new array cell of `count` elements with the header `info` (kind
 * IDRIS_RT_KIND_ARRAY), counted as idris_rt_cell counts a cell. When its
 * elements hold objects, every byte of them is 0, so every object slot is
 * NULL until a store; otherwise they are not written. The first element is
 * aligned to IDRIS_RT_WORD_BYTES. Exhausted memory, and a count whose cell
 * would not fit the address space (UINT64_MAX, for an element of a byte or
 * more), end the process with a crash. */
idris_rt_array *idris_rt_array_new(uint64_t count, uint32_t info);

/* memref.copy, where idr-lower does not copy the bytes itself: each element
 * of the view `from` assigned to the same place of the view `to`, in
 * row-major order. Both have rank `rank` and from's sizes. The element is
 * the one to's cell describes, and from's cell holds the same: each object
 * slot copied gains one reference, then the slot it overwrites loses one,
 * then the element's bytes are moved. So a cell fresh from
 * idris_rt_array_new may be the target as it is, and a view copied onto
 * itself, the one overlap allowed, is left as it was. */
void idris_rt_memref_copy(int64_t rank, const idris_rt_memref *from, const idris_rt_memref *to);

/* One more owned reference; a count that would reach UINT32_MAX saturates
 * there. */
void idris_rt_inc(void *o);

/* One owned reference less. At 0 the object is released: a box's or a
 * thunk's object slots lose a reference each, and then its memory is freed
 * (a stack cell's is not). Objects that reach 0
 * in turn are released the same way, from a worklist that runs through the
 * dying cells themselves: no recursion and no allocation, so freeing takes
 * constant stack however deep the structure is. */
void idris_rt_dec(void *o);

/* Releases what a persistent memo cell holds (its object slots), once,
 * when the program ends: @__idr_release_cafs calls it on each of the
 * module's static thunks. A cell that was never forced holds only
 * persistent captures, and then nothing is released. */
void idris_rt_caf_release(void *cell);

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
 * single-threaded, and idris-mlir reads it before and after each fold, on
 * the thread that folds, with no atomic operation on the allocation path. */
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
/* What @main calls right before it returns: writes pending output and
 * releases the handle table (its files, directories, and the strings the
 * runtime holds for environment and directory handles, which are then not
 * counted as live), then, when the environment variable IDRIS_RT_LIVE is
 * exactly "1", writes the line "idris-rt: live cells N\n" (N in decimal,
 * idris_rt_live_cells) to standard error, so a test can check that a program
 * frees every cell it allocates. A crash reports nothing, and neither does
 * idris_rt_io_exit. */
void idris_rt_main_return(void);
/* idris_rt_io_put_str writes a string's bytes. idris_rt_io_put_char writes
 * the UTF-8 encoding of a character: the Prelude's putChar, and what writing
 * a one-character string writes. A Char is a Unicode scalar value, so it is
 * written whole, where both stock backends call C's putchar, as the Prelude
 * declares putChar, and write its low byte. idris_rt_io_put_int_s and
 * idris_rt_io_put_int_u write the decimal text of a signed or an unsigned
 * integer, which idr-lower extends to 64 bits as its type's signedness says.
 * idris_rt_io_put_double writes the text of a double, as
 * idris_rt_str_show_f64 writes it. */
/* A string built in place by idr.str.pack and idr.str.concat, which know
 * its size from a first pass: a new string of `bytes` bytes and `scalars`
 * scalar values (`ascii` nonzero when every byte is ASCII), whose bytes
 * the caller then writes in order, a character's UTF-8 or a string's
 * bytes at an offset, each giving the next offset. The empty string is
 * shared and never written. */
idris_rt_str *idris_rt_str_alloc(int64_t bytes, int64_t scalars, int32_t ascii);
int64_t idris_rt_str_put_char(idris_rt_str *s, int64_t offset, int32_t c);
int64_t idris_rt_str_put_str(idris_rt_str *s, int64_t offset, const idris_rt_str *part);
/* idris_rt_str_bytes_length gives the byte length of a string, and
 * idris_rt_str_is_ascii whether every byte of it is ASCII. */
int32_t idris_rt_str_is_ascii(const idris_rt_str *s);
/* idris_rt_io_get_byte reads one byte, or gives 255 at the end of input.
 * idris_rt_io_get_line reads a line of input without its end, the Prelude's
 * getLine: the bytes up to the next '\n', which is consumed, without that
 * '\n' or the "\r\n" it ends; the rest of the input when no '\n' is left,
 * and the empty string at the end of input. The bytes are decoded as
 * idris_rt_str_from_bytes decodes them. A new string. */
/* A byte array (a Data.Buffer) is passed as its cell, its first byte (the
 * cell's first element, which idr-lower computes at the call) and its size.
 * Only the first byte is read: every span lies in the array, since
 * idr.check.range tests it against the size before the call, and an address
 * in the array is `bytes + offset`, which need not be aligned. */
/* idris_rt_io_write_bytes writes the bytes [offset, offset + count) of a
 * byte array to a handle: 1 is standard output, through the output buffer
 * and in order with every other write to it; 2 is standard error; any other
 * is a file the program opened (idris_rt_io_file_open). Gives the count
 * written.
 * idris_rt_io_read_bytes reads bytes from a handle into [offset, offset +
 * count) of a byte array: 0 is standard input, through the input buffer
 * idris_rt_io_get_line reads too, and any other a file the program opened.
 * Gives the count read, 0 at the end of input.
 * idris_rt_io_eof gives 1 once a read on the handle met the end of its
 * input, as C's feof reports it, else 0: standard input, or a file the
 * program opened.
 * idris_rt_io_n_processors gives how many processors are online, read when
 * asked; -1 when the system does not say, which System.Info.getNProcessors
 * turns into Nothing.
 * idris_rt_io_buffer_copy copies `len` bytes from one byte array to
 * another. The ranges may overlap.
 * idris_rt_io_buffer_set_string writes a string's bytes at `offset`. The
 * span is the string's byte length.
 * idris_rt_io_buffer_get_string gives the bytes [offset, offset + len) of a
 * byte array as a string. Ill-formed UTF-8 is replaced as
 * idris_rt_str_from_bytes replaces it. A new string. */

/* Base's files, directories, process, terminal, errors and clocks
 * (System.File, System.Directory, System, System.Term, System.Errno,
 * System.Clock): each is the op idr.io.<name> or idr.handle.<name>, whose
 * one meaning is documented beside its definition, the same on both
 * targets. Their arguments are borrowed, and a string they return is new.
 *
 * A pointer of base is a handle, an int64_t: 0, 1 and 2 are the standard
 * streams, -1 is null, and any other is a slot of the runtime's handle table,
 * which holds a file, a directory, a file time or a string. A string handle
 * read from a file (idris_rt_io_file_read_line, idris_rt_io_file_read_chars)
 * or naming the current directory (idris_rt_io_dir_current) is the
 * program's, which frees it (idris_rt_io_handle_free); one from
 * idris_rt_io_env_get, idris_rt_io_env_pair or idris_rt_io_dir_entry is the
 * runtime's, as getenv's and readdir's bytes are the C library's: the next
 * call of its kind, or closing its directory, releases it, and freeing its
 * handle does nothing. An OSClock is seconds << 30 | nanoseconds, or -1 when
 * it is not valid. A failing call sets the runtime's saved errno, which
 * idris_rt_io_errno and idris_rt_io_file_errno read.
 * idris_rt_io_exit writes pending output and ends the process with the
 * status, reporting no live cells. idris_rt_handle_is_null gives 1 when the
 * handle is null (-1), else 0. idris_rt_handle_string gives the string a
 * string handle holds, with one more reference. */
/* Writes pending output, then the len bytes of msg to standard error, then
 * ends the process with status IDRIS_RT_CRASHED: lowered code crashes
 * through it alone. */
IDRIS_RT_NORETURN void idris_rt_crash(const char *msg, size_t len);
/* idris_rt_crash_str ends the program with "idris-mlir: " and the string's
 * bytes. */

/* The exit status of a program that the runtime ends with a message on
 * standard error ("idris-mlir: <cause>"): a crash, the stack running out, a
 * CPU without the features the program was compiled to use, a system whose
 * page size is not the one the runtime is built for. */
#define IDRIS_RT_CRASHED 1

/* The program's entry, which @main calls with the program, the
 * IDRIS_RT_CPU_FEATURES bits its target enables (cpu_features.h), and its
 * own argc and argv, which the runtime keeps for idris_rt_io_arg_count and
 * idris_rt_io_arg. First,
 * when the system's page size is not the target's the runtime is built for,
 * it names both and ends the process with IDRIS_RT_CRASHED. When the
 * CPU lacks one of them, it names them and ends the process with
 * IDRIS_RT_CRASHED before the program runs; it is compiled for the target's baseline, and idris-mlir
 * keeps it there. Otherwise it runs body on a reserved stack
 * (idris_rt_run_on_stack) of the number of bytes the environment variable
 * IDRIS_RT_STACK says, or else of a gibibyte, or of the stack limit when
 * that is larger; when that stack runs out, the output written so far is flushed,
 * "idris-mlir: stack exhausted" is written to standard error, and the
 * process ends with IDRIS_RT_CRASHED. What body returns is the exit status:
 * it returns a status from 0 to 255, and ends the process as a crash that
 * names any other value, which no parent could tell from its low 8 bits. */
int idris_rt_start(int64_t (*body)(void), uint64_t cpu_features, int argc, char **argv);

/* The reserved-stack runner, which programs and idris-mlir share: runs
 * fn(arg) on a new thread whose stack is reserved address space, committed
 * as it is touched, of the largest size from `most` bytes down by halves to
 * 64 MiB (or `most`, when smaller) that the machine grants, with `guard`
 * inaccessible bytes below it. Both are rounded up to whole pages, and the
 * guard is at least one. A fault on the guard is the stack running out:
 * exhausted() runs, on a signal stack of its own, and must end the process
 * with only async-signal-safe calls. Any other fault gets the action it had
 * before. One runner runs at a time in a process. It checks the page size
 * first, as idris_rt_start does. Returns 0 once fn has returned, or -1 when
 * no stack could be reserved. */
int idris_rt_run_on_stack(void (*fn)(void *), void *arg, size_t most, size_t guard,
                          void (*exhausted)(void));

/* Doubles. idris_rt_to_int gives a double truncated toward zero, modulo
 * 2^64; the double is finite (idr-lower checks it first).
 * idris_rt_double_head gives the first character of the text of a double
 * (idris_rt_str_show_f64): '-', a digit, or the 'i' of inf or the 'n' of
 * nan. idris_rt_int_head_s and idris_rt_int_head_u give the first character
 * of the decimal text of a signed or unsigned integer. */

/* Strings. Strings are immutable; each operation borrows its arguments and
 * returns an owned string: a new one, a persistent one (the empty string), or
 * an argument with one more reference (appending the empty string, reversing
 * an empty one). Preconditions, which idr-lower
 * checks and crashes on before the call: idris_rt_str_index needs
 * 0 <= index < length, idris_rt_str_head and idris_rt_str_tail a nonempty
 * string.
 * - idris_rt_str_append, idris_rt_str_cons, idris_rt_str_from_char: the
 *   concatenation of two strings, a character before a string, the string
 *   of one character.
 * - idris_rt_str_show_s, idris_rt_str_show_u: the decimal text of a signed
 *   or an unsigned integer.
 * - idris_rt_str_show_f64: the text of a double, which reads back as it
 *   (idris_rt_str_to_double): the fewest significant digits that do, the
 *   nearest of those to the double, and of two equally near the one whose
 *   last digit is even; positional from 1e-3 up to 1e10, with a digit after
 *   the point (0.001, 100.0), else in scientific notation (1e21, 1.5e-7,
 *   5e-324); inf, -inf and nan, a NaN whatever its sign; -0.0 with its sign.
 * - idris_rt_str_length: the number of scalar values; idris_rt_str_index,
 *   idris_rt_str_head: the scalar at an index, the first; idris_rt_str_tail:
 *   the string without its first scalar; idris_rt_str_reverse: its scalars
 *   in reverse order.
 * - idris_rt_str_substr: the Prelude's substr, the scalars from `start`, at
 *   most `length` of them; "" when the start is past the end, and only
 *   those left when fewer than `length` are. A negative start or length,
 *   which only a call of the primitive itself passes, counts as 0. */
/* A string by byte offset, as the linear string iterator walks it. Every
 * offset has a meaning: it is clamped to [0, bytes], and one inside a
 * scalar's encoding stands for the start of that scalar.
 * - idris_rt_str_scalar_at: the scalar that starts there; 0 at the end.
 * - idris_rt_str_scalar_end: the offset after that scalar, which is
 *   greater than the offset when the offset is below the end; the byte
 *   length at the end.
 * - idris_rt_str_drop_bytes: the scalars from there on: the string itself
 *   (one more reference) from 0, the persistent empty one at the end, and
 *   otherwise a new string, which keeps the ASCII flag of the string. */
/* idris_rt_str_cmp gives negative, zero or positive as its first string is
 * before, equal to or after its second in the order of their scalar values,
 * Unicode's code point order, which is the byte order of their UTF-8. */
/* `cast` from String (idris_rt_str_to_int, idris_rt_str_to_double,
 * idris_rt_big_from_str): the whole string is an optional sign (`+` or `-`)
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
 * bitwise operations and the shifts are those of the infinite two's
 * complement representation, as upstream Idris's test suite requires of
 * every backend (its integers test of Chez, RefC and Node); the divisor is
 * nonzero (idr-lower checks it first).
 * - idris_rt_big_add, _sub, _mul, _div, _mod, _and, _or, _xor, _neg: the
 *   arithmetic and the bitwise operations.
 * - idris_rt_big_shl, idris_rt_big_shr: a value moved `amount` places, left
 *   or right, the other way when the amount is negative, as Scheme's ash
 *   moves it: a left shift is value * 2^amount, a right shift the floor of
 *   value / 2^amount, so it fills with the sign. A shift toward zero, and
 *   any shift of 0, is defined for every amount. A left shift whose result
 *   no integer can hold (more than 2^31 - 1 limbs) ends the process as
 *   exhausted memory does.
 * - idris_rt_big_pred: the value minus 1, for a natural that is not zero.
 * - idris_rt_nat_from_big: an Integer as a natural, 0 if it is negative,
 *   else itself (Idris's integerToNat).
 * - idris_rt_big_cmp: negative, zero or positive as its first operand is
 *   less than, equal to or greater than its second.
 * - idris_rt_big_from_int_s, idris_rt_big_from_int_u: a signed or an
 *   unsigned integer as a big.
 * - idris_rt_big_to_int: the value modulo 2^64; idr-lower wraps it to the
 *   op's width.
 * - idris_rt_big_from_double: a double truncated toward zero; it is finite
 *   (idr-lower checks it first).
 * - idris_rt_big_to_double: the double nearest to the value, ties to even,
 *   an infinity past the largest: the conversion of IEEE 754 under its
 *   default rounding.
 * - idris_rt_big_show: its decimal text, a new string.
 * - idris_rt_big_from_str: the integer cast of idris_rt_str_to_int, without
 *   the wrapping. */

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

#ifdef __cplusplus
}
#endif

#endif /* IDRIS_RT_H */
