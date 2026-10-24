// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Bigs as idris_rt.h lays them out, the model runtime-bigs and runtime-text
// hold the runtime's bigs to: operands built in that layout by the test, so
// no runtime parser stands under an oracle, and results read back from it,
// never through a runtime call. GMP is the arithmetic.
#pragma once
#include <gmp.h>
#include "idris_rt.h"
// Through the include path, as every program includes it: prop.h is this
// directory's, which no header reaches by its place beside it.
#include <prop.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// GMP's si and ui functions take a long, which holds a word on both LP64
// targets; the model passes words through them.
static_assert(sizeof(long) == sizeof(int64_t), "a long is a word");

namespace bigmodel::detail {
// v fits the small range, the 63-bit values an odd word holds.
inline bool fitsSmall(mpz_srcptr v) {
  return mpz_cmp_si(v, IDRIS_RT_SMALL_MIN) >= 0 && mpz_cmp_si(v, IDRIS_RT_SMALL_MAX) <= 0;
}
// A large big's cell, copied out of its word's address.
inline idris_rt_bignum cellOf(idris_rt_big b) {
  idris_rt_bignum cell;
  memcpy(&cell, reinterpret_cast<const void *>(b), sizeof cell);
  return cell;
}
// A large big's limbs, right after its cell's bignum.
inline const mp_limb_t *limbsOf(idris_rt_big b) {
  return reinterpret_cast<const mp_limb_t *>(reinterpret_cast<const char *>(b) + sizeof(idris_rt_bignum));
}
} // namespace bigmodel::detail

// Every function below is inline: the header is included by both programs.
namespace bigmodel {
// out = sign * 2^exponent + adjust: how the edges of the families and of
// runtime-bigs' box are written.
inline void nearPower(mpz_ptr out, long sign, unsigned long exponent, long adjust) {
  mpz_t power;
  mpz_init(power);
  mpz_setbit(power, exponent);
  mpz_mul_si(power, power, sign);
  mpz_set_si(out, adjust);
  mpz_add(out, out, power);
  mpz_clear(power);
}
// The largest operand a property draws: past one limb and two, where to_int,
// to_double and the shifts cross limb boundaries, and cheap per case.
inline constexpr size_t maxLimbs = 8;
// Storage for a persistent big laid out as idris_rt.h lays out a large
// big (idris_rt_bignum) and as idr-lower writes one into static data: count 0,
// info idris_rt_info(0, 0, IDRIS_RT_KIND_FIELDS), the signed limb count,
// the limbs least significant first. Aligned to a word.
struct Constant { alignas(8) uint64_t words[2 + maxLimbs]; };
// The big of v (at most maxLimbs limbs): the tagged word 2v + 1 when v
// fits 63 bits, else the persistent bignum written into c.
inline idris_rt_big constant(mpz_srcptr v, Constant &c) {
  // The two representations a big has: a value is small exactly when it fits.
  if (detail::fitsSmall(v))
    return static_cast<idris_rt_big>(static_cast<uint64_t>(mpz_get_si(v)) << 1 | 1);
  size_t limbs = mpz_size(v);
  // A value past the storage is a fault of the property that drew it.
  if (limbs > maxLimbs) {
    fprintf(stderr, "bigmodel: a constant of %zu limbs, past maxLimbs\n", limbs);
    abort();
  }
  // Copied from the layout's own struct, so the bytes are the ones the
  // target lays out, whatever its byte order.
  idris_rt_bignum cell = {{0, idris_rt_info(0, 0, IDRIS_RT_KIND_FIELDS)},
                          mpz_sgn(v) * static_cast<int64_t>(limbs)};
  memcpy(c.words, &cell, sizeof cell);
  for (size_t i = 0; i < limbs; ++i)
    c.words[2 + i] = mpz_getlimbn(v, static_cast<mp_size_t>(i));
  return reinterpret_cast<idris_rt_big>(c.words);
}
// The value of any big, small or large, counted or persistent, read through
// the documented layout alone (mpz_roinit_n on the limbs, never a runtime call).
inline void value(idris_rt_big b, mpz_ptr out) {
  // An odd word is the value shifted left by one and tagged.
  if ((b & 1) != 0) {
    mpz_set_si(out, b >> 1);
    return;
  }
  __mpz_struct view;
  mpz_set(out, mpz_roinit_n(&view, detail::limbsOf(b), static_cast<mp_size_t>(detail::cellOf(b).size)));
}
// One representation: odd exactly when the value fits 63 bits; a large one
// an even word whose cell's info is a bignum's, size not 0, top
// limb not 0, value outside [-2^62, 2^62 - 1]. Says what is wrong (prop::explain).
inline bool canonical(idris_rt_big b) {
  // Every odd word holds some 63-bit value, which is the small form.
  if ((b & 1) != 0)
    return true;
  idris_rt_bignum cell = detail::cellOf(b);
  // A bignum's info: a cell of fields, tag 0, no object slots.
  bool ok = cell.header.info == idris_rt_info(0, 0, IDRIS_RT_KIND_FIELDS);
  if (!ok)
    prop::explain("a large big's info is %#x, where a bignum's is %#x", cell.header.info,
                  idris_rt_info(0, 0, IDRIS_RT_KIND_FIELDS));
  // What follows reads the top limb, which a cell of no limbs lacks.
  if (cell.size == 0) {
    prop::explain("a large big of no limbs");
    return false;
  }
  uint64_t limbs = cell.size < 0 ? 0 - static_cast<uint64_t>(cell.size) : static_cast<uint64_t>(cell.size);
  if (detail::limbsOf(b)[limbs - 1] == 0) {
    prop::explain("a large big of %llu limbs whose top limb is 0", static_cast<unsigned long long>(limbs));
    ok = false;
  }
  mpz_t v;
  mpz_init(v);
  value(b, v);
  if (detail::fitsSmall(v)) {
    prop::explain("a large big whose value fits a small word: %ld", mpz_get_si(v));
    ok = false;
  }
  mpz_clear(v);
  return ok;
}
// The families a big is drawn from, simplest first, and a draw from one.
inline constexpr unsigned families = 8;
inline void draw(FuzzedDataProvider &p, unsigned family, mpz_ptr out) {
  // A value near a power of two: sign * 2^exponent + adjust, moved by
  // step * d for a drawn d in [0, 16], since the off-by-ones a word
  // operation makes at an edge are within that of it. A step of 0 keeps
  // the value itself.
  struct Near {
    long sign;
    unsigned long exponent;
    long adjust;
    long step;
  };
  // The small range's edges, from inside, and +-2^61, past which a sum of
  // two small values leaves it.
  static constexpr Near inside[] = {{-1, 62, 0, 1}, {1, 62, -1, -1}, {1, 61, 0, 0}, {-1, 61, 0, 0}};
  // Just past the small range, and the int64 and uint64 edges: -2^63,
  // 2^63 - 1, 2^63, 2^64 - 1 and +-2^64.
  static constexpr Near outside[] = {{-1, 62, -1, -1}, {1, 62, 0, 1}, {-1, 63, 0, 0}, {1, 63, -1, 0},
                                     {1, 63, 0, 0},    {1, 64, -1, 0}, {1, 64, 0, 0},  {-1, 64, 0, 0}};
  // 2^k, then one off either way.
  static constexpr long offByOne[] = {0, 1, -1};
  auto near = [&](const Near &n) {
    nearPower(out, n.sign, n.exponent, n.adjust + n.step * p.ConsumeIntegralInRange<long>(0, 16));
  };
  // A sign for the families of a magnitude, drawn last, so that an
  // exhausted provider keeps the magnitude's simplest and positive.
  auto withSign = [&] { mpz_mul_si(out, out, p.ConsumeBool() ? -1 : 1); };
  switch (family) {
  case 0: // small: 0, +-1, +-2
    mpz_set_ui(out, p.ConsumeIntegralInRange<unsigned long>(0, 2));
    return withSign();
  case 1: // small, in [-2^20, 2^20]
    mpz_set_ui(out, p.ConsumeIntegralInRange<unsigned long>(0, 1ul << 20));
    return withSign();
  case 2: // the small range's edges
    return near(p.PickValueInArray(inside));
  case 3: // just past them, and the machine words' edges
    return near(p.PickValueInArray(outside));
  case 4: // one limb: any magnitude below 2^64
    mpz_set_ui(out, p.ConsumeIntegral<unsigned long>());
    return withSign();
  case 5: { // 2 to maxLimbs limbs, the top one not 0
    size_t limbs = p.ConsumeIntegralInRange<size_t>(2, maxLimbs);
    unsigned char bytes[8 * maxLimbs] = {};
    p.ConsumeData(bytes, 8 * limbs);
    mpz_import(out, 8 * limbs, -1, 1, 0, 0, bytes);
    mpz_setbit(out, 64 * (limbs - 1));
    return withSign();
  }
  case 6: // +-2^k and +-2^k +- 1
    nearPower(out, 1, p.ConsumeIntegralInRange<unsigned long>(0, 64 * maxLimbs - 1), p.PickValueInArray(offByOne));
    return withSign();
  default: // 7: 2^k - 1 and its negation
    nearPower(out, 1, p.ConsumeIntegralInRange<unsigned long>(0, 64 * maxLimbs), -1);
    return withSign();
  }
}

// The test's own integers and bigs, which both programs hold values in.

// An integer, GMP's, cleared when it goes. GMP's macros (mpz_sgn,
// mpz_cmp_ui) read its fields through ->.
class Z {
public:
  Z() { mpz_init(z_); }
  explicit Z(long v) { mpz_init_set_si(z_, v); }
  ~Z() { mpz_clear(z_); }
  Z(const Z &) = delete;
  Z &operator=(const Z &) = delete;
  operator mpz_ptr() { return z_; }
  operator mpz_srcptr() const { return z_; }
  mpz_ptr operator->() { return z_; }
  mpz_srcptr operator->() const { return z_; }

private:
  mpz_t z_;
};

// An operand: a value and its big, a persistent constant laid out where it
// lives, since a large one's word is its cell's address.
class Operand {
public:
  explicit Operand(mpz_srcptr v) {
    mpz_set(value_, v);
    word_ = constant(value_, cell_);
  }
  explicit Operand(long v) : value_(v) { word_ = constant(value_, cell_); }
  Operand(const Operand &) = delete;
  Operand &operator=(const Operand &) = delete;
  idris_rt_big word() const { return word_; }
  mpz_srcptr value() const { return value_; }

private:
  Z value_;
  Constant cell_;
  idris_rt_big word_;
};

// A big an operation returned, which the test owns and releases when it
// goes, with its value as its layout gives it.
class Result {
public:
  explicit Result(idris_rt_big word) : word_(word) { bigmodel::value(word_, value_); }
  ~Result() { idris_rt_dec_big(word_); }
  Result(const Result &) = delete;
  Result &operator=(const Result &) = delete;
  idris_rt_big word() const { return word_; }
  mpz_srcptr value() const { return value_; }

private:
  idris_rt_big word_;
  Z value_;
};

// A line of an explanation that shows values: GMP's printf writes them.
template <typename... Values> void explainValues(const char *format, Values... values) {
  char line[2048];
  gmp_snprintf(line, sizeof line, format, values...);
  prop::explain("%s", line);
}

// The low 64 bits of v, two's complement: the word to_int gives, and the
// machine integer a big is cast to.
inline uint64_t low64(mpz_srcptr v) {
  Z low;
  mpz_fdiv_r_2exp(low, v, 64);
  return mpz_getlimbn(low, 0);
}
} // namespace bigmodel
