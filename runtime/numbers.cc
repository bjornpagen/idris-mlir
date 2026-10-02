// `cast` from String. Idris documents no syntax for it and its backends
// disagree, so the cast reads what Idris's own syntax writes: a literal of
// the target type, with an optional sign before it, as the whole string.
// Any other string is 0, as a cast is total.
// - Every number type reads an integer literal: decimal digits, or 0b, 0o,
//   0x or 0X and digits of that base, in groups that single underscores may
//   separate (1_000). An integer type takes its value modulo 2^N; Double
//   the nearest double, as fromInteger does.
// - Double also reads a decimal literal, digits, a point and digits, with an
//   optional exponent (e, a sign, digits), and digits with an exponent and
//   no point, which is how a double's text is written when it has one
//   significant digit (1e21): every text of a double reads back as it, as
//   IEEE 754 requires of the two conversions, correctly rounded to nearest,
//   ties to even. It reads inf, infinity and nan, in any case, as IEEE 754
//   spells the infinities and NaN.
// So 12.7 is 0 as an Int, being no literal of one, and .5, 5., 1E3 and
// surrounding spaces are no number at all.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <system_error>

#include <fast_float/fast_float.h>

namespace {

bool isDigit(char c, unsigned base) {
  if (base == 16)
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
  return c >= '0' && c < static_cast<char>('0' + base);
}

// The end of the digits of `base` from `at`.
size_t digitsFrom(const char *p, size_t n, size_t at, unsigned base) {
  while (at < n && isDigit(p[at], base))
    ++at;
  return at;
}

// The end of the digit groups of `base` from `at`, digits that single
// underscores may separate; `grouped` is set when one does.
size_t groupsFrom(const char *p, size_t n, size_t at, unsigned base, bool &grouped) {
  size_t end = digitsFrom(p, n, at, base);
  while (end > at && end + 1 < n && p[end] == '_' && isDigit(p[end + 1], base)) {
    grouped = true;
    end = digitsFrom(p, n, end + 1, base);
  }
  return end;
}

// Whether the n bytes at p are `word`, in any case.
bool isWord(const char *p, size_t n, const char *word) {
  size_t i = 0;
  for (; i < n && word[i] != '\0'; ++i)
    if ((p[i] | 0x20) != word[i])
      return false;
  return i == n && word[i] == '\0';
}

double fromChars(const char *p, size_t n) {
  double value = 0.0;
  auto result = fast_float::from_chars(
      p, p + n, value,
      fast_float::chars_format::general | fast_float::chars_format::allow_leading_plus);
  return result || result.ec == std::errc::result_out_of_range ? value : 0.0;
}

} // namespace

rt::Numeral rt::readNumeral(const char *p, size_t n) {
  Numeral numeral;
  size_t at = 0;
  if (n > 0 && (p[0] == '+' || p[0] == '-')) {
    numeral.negative = p[0] == '-';
    at = 1;
  }
  if (isWord(p + at, n - at, "inf") || isWord(p + at, n - at, "infinity")) {
    numeral.kind = Numeral::Infinity;
    return numeral;
  }
  if (isWord(p + at, n - at, "nan")) {
    numeral.kind = Numeral::NaN;
    return numeral;
  }
  if (n - at > 2 && p[at] == '0') {
    char prefix = p[at + 1];
    unsigned base = prefix == 'b' ? 2 : prefix == 'o' ? 8 : prefix == 'x' || prefix == 'X' ? 16 : 0;
    if (base != 0) {
      if (groupsFrom(p, n, at + 2, base, numeral.grouped) == n) {
        numeral.kind = Numeral::Integer;
        numeral.base = base;
        numeral.digits = at + 2;
      }
      return numeral;
    }
  }
  size_t end = groupsFrom(p, n, at, 10, numeral.grouped);
  if (end == at)
    return numeral;
  numeral.digits = at;
  if (end == n) {
    numeral.kind = Numeral::Integer;
    return numeral;
  }
  if (numeral.grouped)
    return numeral;
  bool point = p[end] == '.';
  if (point) {
    size_t fraction = digitsFrom(p, n, end + 1, 10);
    if (fraction == end + 1)
      return numeral;
    end = fraction;
  }
  if (end < n && p[end] == 'e') {
    size_t exponent = end + 1;
    if (exponent < n && (p[exponent] == '+' || p[exponent] == '-'))
      ++exponent;
    end = digitsFrom(p, n, exponent, 10);
    if (end == exponent)
      return numeral;
  } else if (!point) {
    return numeral;
  }
  if (end == n)
    numeral.kind = Numeral::Decimal;
  return numeral;
}

uint64_t rt::Numeral::wrapped(const char *p, size_t n) const {
  uint64_t value = 0;
  for (size_t i = digits; i < n; ++i) {
    char c = p[i];
    if (c == '_')
      continue;
    uint64_t digit = c <= '9' ? static_cast<uint64_t>(c - '0') : static_cast<uint64_t>((c | 0x20) - 'a' + 10);
    value = value * base + digit;
  }
  return negative ? 0 - value : value;
}

extern "C" double idris_rt_parse_double(const char *p, size_t n) {
  rt::Numeral numeral = rt::readNumeral(p, n);
  switch (numeral.kind) {
  case rt::Numeral::Infinity:
    return numeral.negative ? -__builtin_inf() : __builtin_inf();
  case rt::Numeral::NaN:
    return __builtin_nan("");
  case rt::Numeral::Decimal:
    return fromChars(p, n);
  case rt::Numeral::Integer: {
    if (numeral.base == 10 && !numeral.grouped)
      return fromChars(p, n);
    idris_rt_big magnitude = rt::bigOfDigits(p + numeral.digits, n - numeral.digits, numeral.base);
    double value = idris_rt_big_to_double(magnitude);
    idris_rt_big_release(magnitude);
    return numeral.negative ? -value : value;
  }
  case rt::Numeral::None:
    break;
  }
  return 0.0;
}

extern "C" double idris_rt_str_to_double(const idris_rt_str *s) {
  return idris_rt_parse_double(idris_rt_str_bytes(s), s->bytes);
}

extern "C" int64_t idris_rt_str_to_int(const idris_rt_str *s) {
  const char *p = idris_rt_str_bytes(s);
  rt::Numeral numeral = rt::readNumeral(p, s->bytes);
  if (numeral.kind != rt::Numeral::Integer)
    return 0;
  return static_cast<int64_t>(numeral.wrapped(p, s->bytes));
}
