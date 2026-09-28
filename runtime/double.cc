// Doubles as text and as integers.
//
// The digits are Ryu's (Adams, PLDI 2018; third_party/ryu, unmodified): the
// shortest that read back as the same double, the closest when there are
// several. Where two are equally close Ryu takes the even one, and Chez
// Scheme, whose number->string is the reference (Burger and Dybvig's
// free-format algorithm), the larger. So the wrapper checks, with exact
// integer arithmetic, whether Ryu's digits D are the lower of two equally
// close candidates, that is whether x = (D + 1/2) * 10^e; if so it takes
// D + 1. Both candidates are in the rounding interval then: they are equally
// far from x, and the interval is no narrower above x than below it. Ryu
// rounds such a tie to even, so D is even and D + 1 needs no carry.
// The layout is Chez's. The text is written through a volatile pointer, so
// that LLVM makes no memcpy or memset of its loops.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <ryu/ryu.h>

namespace {

constexpr uint64_t mantissaBits = 52;
constexpr uint64_t mantissaMask = (uint64_t{1} << mantissaBits) - 1;
constexpr uint64_t exponentMask = 0x7FF;

uint64_t bitsOf(double x) { return __builtin_bit_cast(uint64_t, x); }

// value * 5^n, or nothing when that is `limit` or more.
bool timesPowerOfFive(uint64_t value, int32_t n, uint64_t limit, uint64_t &result) {
  for (int32_t i = 0; i < n; ++i) {
    if (value >= limit / 5)
      return false;
    value *= 5;
  }
  result = value;
  return value < limit;
}

// Whether the positive double m2 * 2^e2 is exactly (10 * digits + 5) *
// 10^(e10 - 1): the lower candidate of an exact tie.
bool isLowerTie(uint64_t m2, int32_t e2, uint64_t digits, int32_t e10) {
  uint64_t n = 10 * digits + 5;
  auto zeros = static_cast<int32_t>(__builtin_ctzll(m2));
  uint64_t odd = m2 >> zeros;
  int32_t twos = e2 + zeros;
  int32_t p = e10 - 1;
  uint64_t scaled;
  // n is odd, so both sides must have the same power of two and odd part.
  if (p >= 0)
    return twos == p && timesPowerOfFive(n, p, uint64_t{1} << 53, scaled) && scaled == odd;
  return twos == p && timesPowerOfFive(odd, -p, uint64_t{1} << 62, scaled) && scaled == n;
}

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
    return mantissa != 0 ? put(out, "+nan.0") : negative ? put(out, "-inf.0") : put(out, "+inf.0");
  if (exponent == 0 && mantissa == 0)
    return negative ? put(out, "-0.0") : put(out, "0.0");

  // Ryu's scientific text: [-]d[.ddd]E[-]x.
  char ryu[32];
  auto ryuLength = static_cast<size_t>(d2s_buffered_n(x, ryu));
  char digits[20];
  size_t count = 0;
  size_t i = negative ? 1 : 0;
  uint64_t d = 0;
  for (; ryu[i] != 'E'; ++i)
    if (ryu[i] != '.') {
      d = 10 * d + static_cast<uint64_t>(ryu[i] - '0');
      ++count;
    }
  bool negativeExponent = ryu[++i] == '-';
  if (negativeExponent)
    ++i;
  int32_t scientific = 0;
  for (; i < ryuLength; ++i)
    scientific = 10 * scientific + (ryu[i] - '0');
  if (negativeExponent)
    scientific = -scientific;
  int32_t e10 = scientific - static_cast<int32_t>(count) + 1;

  uint64_t m2 = exponent == 0 ? mantissa : mantissa | (uint64_t{1} << mantissaBits);
  int32_t e2 = static_cast<int32_t>(exponent == 0 ? 1 : exponent) - 1075;
  if (isLowerTie(m2, e2, d, e10))
    ++d;
  char *first = rt::formatUnsigned(d, digits + sizeof digits);
  auto olen = static_cast<size_t>(digits + sizeof digits - first);
  int32_t e = e10 + static_cast<int32_t>(olen) - 1;

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
  if (exponent == 0) {
    // A subnormal ends with its precision in bits, as Chez prints it.
    out[at++] = '|';
    char text[rt::intTextMax];
    char *end = text + sizeof text;
    char *start = rt::formatUnsigned(64 - static_cast<uint64_t>(__builtin_clzll(mantissa)), end);
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
