// Doubles as text and as integers.
//
// Idris leaves the text of a Double to each backend, and IEEE 754 fixes
// what it must do: read back as the same double, and spell the infinities
// and NaN as `inf` and `nan`. The rest is ours. A finite double is written
// with the fewest significant digits that read back as it; of those, the
// nearest to it, and of two equally near, the even one, as IEEE 754's
// default rounding breaks a tie. Those are Ryu's digits (third_party/ryu,
// unmodified). The layout is the stock Chez backend's, so that the oracle
// compares every text: positional from 1e-3 up to 1e10, with a digit after
// the point, else `d.ddde-x`. Every text reads back through `cast` from
// String. A NaN is `nan` whatever its sign, which IEEE 754 gives no meaning
// and which x86-64 and arm64 set differently for the same operation.
// The text is written through a volatile pointer, so that LLVM makes no
// memcpy or memset of its loops.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <ryu/ryu.h>

namespace {

constexpr uint64_t mantissaBits = 52;
constexpr uint64_t mantissaMask = (uint64_t{1} << mantissaBits) - 1;
constexpr uint64_t exponentMask = 0x7FF;

uint64_t bitsOf(double x) { return __builtin_bit_cast(uint64_t, x); }

template <size_t N> size_t put(volatile char *out, const char (&text)[N]) {
  for (size_t i = 0; i + 1 < N; ++i)
    out[i] = text[i];
  return N - 1;
}

} // namespace

size_t rt::formatDouble(double x, volatile char *out) {
  uint64_t bits = bitsOf(x);
  bool negative = (bits >> 63) != 0;
  uint64_t mantissa = bits & mantissaMask;
  uint64_t exponent = (bits >> mantissaBits) & exponentMask;
  if (exponent == exponentMask)
    return mantissa != 0 ? put(out, "nan") : negative ? put(out, "-inf") : put(out, "inf");
  if (exponent == 0 && mantissa == 0)
    return negative ? put(out, "-0.0") : put(out, "0.0");

  // Ryu's scientific text: [-]d[.ddd]E[-]x.
  char ryu[32];
  auto ryuLength = static_cast<size_t>(d2s_buffered_n(x, ryu));
  char first[17];
  size_t olen = 0;
  size_t i = negative ? 1 : 0;
  for (; ryu[i] != 'E'; ++i)
    if (ryu[i] != '.')
      first[olen++] = ryu[i];
  bool negativeExponent = ryu[++i] == '-';
  if (negativeExponent)
    ++i;
  int32_t e = 0;
  for (; i < ryuLength; ++i)
    e = 10 * e + (ryu[i] - '0');
  if (negativeExponent)
    e = -e;

  size_t at = 0;
  if (negative)
    out[at++] = '-';
  if (e >= -3 && e <= 9) {
    if (e >= 0) {
      auto whole = static_cast<size_t>(e) + 1;
      for (size_t k = 0; k < whole; ++k)
        out[at++] = k < olen ? first[k] : '0';
      out[at++] = '.';
      if (olen > whole)
        for (size_t k = whole; k < olen; ++k)
          out[at++] = first[k];
      else
        out[at++] = '0';
    } else {
      out[at++] = '0';
      out[at++] = '.';
      for (int32_t k = 0; k < -e - 1; ++k)
        out[at++] = '0';
      for (size_t k = 0; k < olen; ++k)
        out[at++] = first[k];
    }
  } else {
    out[at++] = first[0];
    if (olen > 1) {
      out[at++] = '.';
      for (size_t k = 1; k < olen; ++k)
        out[at++] = first[k];
    }
    out[at++] = 'e';
    char text[rt::intTextMax];
    char *end = text + sizeof text;
    char *start = rt::formatSigned(e, end);
    while (start != end)
      out[at++] = *start++;
  }
  return at;
}

extern "C" int32_t idris_rt_double_head(double x) {
  char text[rt::doubleTextMax];
  rt::formatDouble(x, text);
  return text[0];
}

// |x| = m * 2^e, truncated by shifting; then the sign, modulo 2^64.
extern "C" int64_t idris_rt_to_int(double x) {
  uint64_t bits = bitsOf(x);
  uint64_t exponent = (bits >> mantissaBits) & exponentMask;
  uint64_t m = exponent == 0 ? bits & mantissaMask : (bits & mantissaMask) | (uint64_t{1} << mantissaBits);
  int64_t e = static_cast<int64_t>(exponent) - 1075;
  uint64_t magnitude;
  if (e >= 0)
    magnitude = e >= 64 ? 0 : m << e;
  else
    magnitude = -e >= 64 ? 0 : m >> -e;
  return static_cast<int64_t>((bits >> 63) != 0 ? 0 - magnitude : magnitude);
}
