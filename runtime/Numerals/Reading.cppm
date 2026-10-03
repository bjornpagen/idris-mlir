// rt.numerals:reading: what `cast` from String reads in a string.
// PIN(runtime-quarantine) — see PINS.md
module;
#include <stddef.h>
#include <stdint.h>

export module rt.numerals:reading;

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

} // namespace

export namespace rt::numerals {

// What `cast` from String reads in a string: an integer literal, which
// every number type reads; a decimal literal, infinity or NaN, which Double
// reads too; or no number.
struct Numeral {
  enum Kind { None, Integer, Decimal, Infinity, NaN };
  Kind kind = None;
  bool negative = false;
  // An integer literal's base, and where its digits start.
  unsigned base = 10;
  size_t digits = 0;
  // Whether underscores separate its digits.
  bool grouped = false;

  // The integer literal's value, of the n bytes at p it was read from,
  // modulo 2^64.
  uint64_t wrapped(const char *p, size_t n) const;
};

uint64_t Numeral::wrapped(const char *p, size_t n) const {
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

Numeral readNumeral(const char *p, size_t n) {
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

} // namespace rt::numerals
