// What the runtime's sources share and do not export.
// PIN(runtime-quarantine) — see PINS.md
#pragma once

#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

namespace rt {

// True in an evaluation child once idris_rt_eval_begin ran: every allocation
// then comes from the arena, every cell is persistent, and nothing is freed.
extern bool arenaActive;

// Raw memory, which is not a cell (GMP's limbs, scratch buffers): from the
// arena in an evaluation child, from snmalloc otherwise. Exhausted memory is
// a crash.
void *allocate(size_t size);
void release(void *block);

// A cell of `size` bytes with the header {1, info}, counted as live; in an
// evaluation child, from the arena with the header {0, info}: persistent, and
// not counted. Exhausted memory is a crash.
void *newCell(size_t size, uint32_t info);
// Frees the memory of a counted heap cell, which an evaluation child never
// has, and stops counting it.
void freeCell(void *cell);

// Frees a bignum's limbs, and leaves its cell alone.
void clearBignum(idris_rt_bignum *b);

// Writes n bytes to fd, looping over partial writes; a failed write abandons
// the rest.
void writeAll(int fd, const char *p, size_t n);

// The longest text formatDouble writes: a sign, 17 digits, a point, the
// zeros of 1e-3 or an exponent, and a subnormal's `|52`.
constexpr size_t doubleTextMax = 48;
// The text of a double, as Chez writes it; returns its length.
size_t formatDouble(double x, volatile char *out);

// The decimal digits of an integer, written backwards from `end`; returns
// where they start.
char *formatUnsigned(uint64_t value, char *end);
char *formatSigned(int64_t value, char *end);
constexpr size_t intTextMax = 20;

// The UTF-8 encoding of c into out, which has room for 4 bytes; returns its
// length.
size_t encodeUtf8(int32_t c, char *out);

// A new string of `bytes` bytes that the caller fills, with its scalar count
// and ASCII flag, and where its bytes go.
idris_rt_str *newString(uint64_t bytes, uint64_t scalars, bool ascii);
char *mutableBytes(idris_rt_str *s);

// A string from bytes that are well-formed UTF-8.
const idris_rt_str *stringOf(const char *p, size_t n);

// Whether the n bytes at p are a sign and decimal digits, the syntax of an
// integer that `cast` reads exactly; `digits` is where the digits start.
bool isInteger(const char *p, size_t n, size_t &digits);

// Makes GMP allocate through the runtime (idris_rt_gmp_init), once.
void gmpReady();

} // namespace rt
