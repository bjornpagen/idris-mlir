// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Doubles as text and text as doubles, held to IEEE 754 and to the runtime's
// own words. show_f64 writes the fewest significant digits that read back
// as the double, the nearest of those, ties to the even digit, in the
// runtime's layout; str_to_double reads every decimal text as the C
// library's strtod does, integer literals of every base as their nearest
// double, IEEE 754's words, and anything else as 0.0; to_int truncates
// modulo 2^64. Every claim about digits is judged on the exact interval of
// the reals that round to the double, in GMP's rationals, so no printer and
// no reader stands under the oracle.
#include "idris_rt.h"
#include "prop.h"

#include <gmp.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

namespace {

// IEEE 754's binary64: a sign bit, 11 bits of exponent, 52 of significand.
constexpr unsigned significandBits = 52;
constexpr uint64_t significandMask = (uint64_t{1} << significandBits) - 1;
constexpr uint64_t exponentMask = 0x7FF;
constexpr uint64_t signBit = uint64_t{1} << 63;
uint64_t bitsOf(double x) { return __builtin_bit_cast(uint64_t, x); }
double doubleOf(uint64_t bits) { return __builtin_bit_cast(double, bits); }
uint64_t exponentOf(uint64_t bits) { return bits >> significandBits & exponentMask; }

// A finite double's magnitude as significand * 2^scale. IEEE 754 encodes
// two kinds: a normal double's significand has a hidden leading bit and its
// field e gives the scale e - 1075 (the bias, 1023, and the 52 bits after
// the point); a subnormal's (field 0) has none and is scaled as field 1's.
struct Binary {
  uint64_t significand;
  long scale;
};
Binary binaryOf(double magnitude) {
  uint64_t bits = bitsOf(magnitude);
  uint64_t field = exponentOf(bits);
  uint64_t hidden = field > 0 ? uint64_t{1} << significandBits : 0;
  return {(bits & significandMask) | hidden, static_cast<long>(field > 0 ? field : 1) - 1075};
}
bool negativeBit(double x) { return (bitsOf(x) & signBit) != 0; }
// Neither a zero nor, with its exponent all ones, an infinity or a NaN.
bool finiteNonzero(double x) {
  uint64_t bits = bitsOf(x);
  return exponentOf(bits) != exponentMask && (bits & ~signBit) != 0;
}

// A double for an explanation: C's hexadecimal float and its bits.
struct Named {
  char text[64];
  explicit Named(double x) {
    snprintf(text, sizeof text, "%a (bits %016llx)", x, static_cast<unsigned long long>(bitsOf(x)));
  }
};

// GMP's rationals and integers, cleared when they go.
struct Q {
  mpq_t v;
  Q() { mpq_init(v); }
  ~Q() { mpq_clear(v); }
  Q(const Q &) = delete;
  Q &operator=(const Q &) = delete;
};
struct Z {
  mpz_t v;
  Z() { mpz_init(v); }
  ~Z() { mpz_clear(v); }
  Z(const Z &) = delete;
  Z &operator=(const Z &) = delete;
};

// 10^k, for any k.
void powerOfTen(mpq_t out, long k) {
  mpz_ui_pow_ui(mpq_numref(out), 10, static_cast<unsigned long>(k < 0 ? -k : k));
  mpz_set_ui(mpq_denref(out), 1);
  if (k < 0)
    mpq_inv(out, out);
}

// floor(log10 v) for v > 0, from an estimate, by exact comparison with
// powers of ten.
long decade(const mpq_t v, long estimate) {
  Q p;
  long m = estimate;
  for (powerOfTen(p.v, m); mpq_cmp(v, p.v) < 0; powerOfTen(p.v, m))
    --m;
  for (powerOfTen(p.v, m + 1); mpq_cmp(v, p.v) >= 0; powerOfTen(p.v, m + 1))
    ++m;
  return m;
}

// The multiple of s nearest v from below (floor) or from above (ceiling).
void multipleBelow(mpq_t out, const mpq_t v, const mpq_t s) {
  Z n;
  mpq_div(out, v, s);
  mpz_fdiv_q(n.v, mpq_numref(out), mpq_denref(out));
  mpq_set_z(out, n.v);
  mpq_mul(out, out, s);
}
void multipleAbove(mpq_t out, const mpq_t v, const mpq_t s) {
  Z n;
  mpq_div(out, v, s);
  mpz_cdiv_q(n.v, mpq_numref(out), mpq_denref(out));
  mpq_set_z(out, n.v);
  mpq_mul(out, out, s);
}

// The reals that round to a finite double of magnitude X under IEEE 754's
// default rounding, to nearest with ties to even: from the midpoint with
// the double below to the midpoint with the double above, both ends
// included exactly when X's significand is even. The double below is
// nextafter's: 0 below the smallest subnormal, and half a step down below a
// power of two. The double above is X plus the weight of X's last
// significand bit, which is nextafter's for every double but the largest
// finite, where it is the next an unbounded exponent would give: its
// midpoint is IEEE 754's overflow threshold.
struct Interval {
  Q lo, hi;
  bool even;
  explicit Interval(double magnitude) {
    uint64_t bits = bitsOf(magnitude);
    even = (bits & 1) == 0;
    Q x, step;
    mpq_set_d(x.v, magnitude);
    mpq_set_d(lo.v, nextafter(magnitude, 0.0));
    mpq_add(lo.v, lo.v, x.v);
    mpq_div_2exp(lo.v, lo.v, 1);
    mpq_set_d(step.v, ldexp(1.0, static_cast<int>(binaryOf(magnitude).scale)));
    mpq_div_2exp(step.v, step.v, 1);
    mpq_add(hi.v, x.v, step.v);
  }
  bool contains(const mpq_t v) const {
    int low = mpq_cmp(v, lo.v);
    int high = mpq_cmp(v, hi.v);
    return (low > 0 || (low == 0 && even)) && (high < 0 || (high == 0 && even));
  }
};

// The longest text the runtime's layout writes: a sign, a digit, a point,
// 16 more digits, then `e-308` (24 bytes); a positional text is shorter.
constexpr size_t longestText = 24;

// A finite nonzero double's text read back: its sign, its significant
// digits D, the first not 0, and the decimal exponent E of D's first
// digit, so that its value is D * 10^(E - len(D) + 1).
struct Decimal {
  bool negative = false;
  char digits[longestText + 1] = {};
  size_t length = 0;
  long exponent = 0;
};

bool isDigit(char c) { return c >= '0' && c <= '9'; }

// The n bytes at t read as `-`? digits (`.` digits)? (`e` `-`? digits)?
// with a digit not 0: false for any other text. D is the digits from the
// first that is not 0, the point dropped; the positional form writes zeros
// to place its point, so there D ends at its last digit not 0, while the
// scientific form's mantissa is D as it is written. E is where D's first
// digit stands from the point, plus the written exponent. The layout check
// writes the text again from what is read here and compares bytes, so this
// reading accepts more than the layout and decides nothing about it.
bool readDecimal(const char *t, size_t n, Decimal &d) {
  if (n > longestText)
    return false;
  size_t i = 0;
  d.negative = n > 0 && t[0] == '-';
  if (d.negative)
    ++i;
  char all[longestText];
  size_t count = 0;
  while (i < n && isDigit(t[i]))
    all[count++] = t[i++];
  size_t point = count;
  if (point == 0)
    return false;
  if (i < n && t[i] == '.') {
    ++i;
    while (i < n && isDigit(t[i]))
      all[count++] = t[i++];
    if (count == point)
      return false;
  }
  bool scientific = i < n && t[i] == 'e';
  long written = 0;
  if (scientific) {
    ++i;
    bool negative = i < n && t[i] == '-';
    if (negative)
      ++i;
    // A double's decimal exponent has at most 3 digits.
    size_t start = i;
    while (i < n && isDigit(t[i]) && i - start < 3)
      written = 10 * written + (t[i++] - '0');
    if (i == start)
      return false;
    if (negative)
      written = -written;
  }
  if (i != n)
    return false;
  size_t first = 0;
  while (first < count && all[first] == '0')
    ++first;
  if (first == count)
    return false;
  size_t end = count;
  while (!scientific && all[end - 1] == '0')
    --end;
  d.length = end - first;
  memcpy(d.digits, all + first, d.length);
  d.digits[d.length] = '\0';
  d.exponent = written + static_cast<long>(point) - 1 - static_cast<long>(first);
  return true;
}

// The text the runtime's layout writes for (sign, D, E): positional when E
// is in [-3, 9], which is "from 1e-3 up to 1e10" (and Printing.cpp's
// choice), with a digit after the point; else D's first digit, the rest
// after a point when there is a rest, `e` and E. Returns its length; out
// has room for 64. `top`, the last positional E, is 9 but for a mutant's.
size_t layout(const Decimal &d, char *out, long top = 9) {
  size_t at = 0;
  if (d.negative)
    out[at++] = '-';
  long e = d.exponent;
  if (e >= -3 && e <= top) {
    if (e >= 0) {
      auto whole = static_cast<size_t>(e) + 1;
      for (size_t k = 0; k < whole; ++k)
        out[at++] = k < d.length ? d.digits[k] : '0';
      out[at++] = '.';
      for (size_t k = whole; k < d.length; ++k)
        out[at++] = d.digits[k];
      if (d.length <= whole)
        out[at++] = '0';
    } else {
      out[at++] = '0';
      out[at++] = '.';
      for (long k = 0; k < -e - 1; ++k)
        out[at++] = '0';
      for (size_t k = 0; k < d.length; ++k)
        out[at++] = d.digits[k];
    }
  } else {
    out[at++] = d.digits[0];
    if (d.length > 1) {
      out[at++] = '.';
      for (size_t k = 1; k < d.length; ++k)
        out[at++] = d.digits[k];
    }
    at += static_cast<size_t>(snprintf(out + at, 64 - at, "e%ld", e));
  }
  return at;
}

// The text IEEE 754 and the runtime fix for a double with no digits to
// choose: a NaN, whatever its sign; an infinity; a zero, with its sign.
const char *wordFor(double x) {
  if (x != x)
    return "nan";
  if (x == 0.0)
    return negativeBit(x) ? "-0.0" : "0.0";
  return negativeBit(x) ? "-inf" : "inf";
}

// The faults each check must notice, planted where it reads the runtime
// (prop.h): most are the mistakes a printer or a reader of doubles makes,
// at the edges where its cases must reach them (a digit too many or too
// few, a tie, the layout's turn, the fast path's 19 digits, 2^63).
constexpr prop::Mutant dropsDigit{"writes the shortest text's last digit dropped"};
constexpr prop::Mutant seventeenDigits{"writes 17 significant digits, as %.17g does"};
constexpr prop::Mutant otherNeighbour{"writes the other text of as many digits that reads back, where there is one"};
constexpr prop::Mutant scientificAt1e9{"turns to the scientific form at 1e9, not 1e10"};
constexpr prop::Mutant positiveZero{"has put_double write a negative zero as 0.0"};
constexpr prop::Mutant truncatesAt19{"reads a decimal text's digits past the 19th significant one as zeros"};
constexpr prop::Mutant literalModulo{"reads an integer literal modulo 2^64"};
constexpr prop::Mutant lowercaseWords{"reads inf, infinity and nan in lower case only, else 0.0"};
constexpr prop::Mutant leadingPoint{"reads a text that starts at its point, such as .5, as strtod does"};
constexpr prop::Mutant sixteenDigits{"writes 16 significant digits, as %.16g does"};
constexpr prop::Mutant saturates{"gives to_int of a double past the int64 range as -2^63, as x86's conversion does"};
constexpr prop::Mutant subnormalsAsZero{"writes a subnormal as a zero"};
constexpr prop::Mutant extraReference{"gives show_f64's text one reference too many"};

// x's magnitude to n significant digits, correctly rounded as printf's %.*e
// writes it, the trailing zeros dropped as %g drops them; with x's sign.
void printfDigits(double x, int n, Decimal &d) {
  char text[64];
  snprintf(text, sizeof text, "%.*e", n - 1, fabs(x));
  d.negative = negativeBit(x);
  d.length = 0;
  const char *at = text;
  for (; *at != 'e'; ++at)
    if (isDigit(*at))
      d.digits[d.length++] = *at;
  d.exponent = strtol(at + 1, nullptr, 10);
  while (d.length > 1 && d.digits[d.length - 1] == '0')
    --d.length;
  d.digits[d.length] = '\0';
}

// The exact value of a Decimal's magnitude: D * 10^(E - len(D) + 1).
void decimalValue(const Decimal &d, mpq_t out) {
  Q scale;
  mpz_set_str(mpq_numref(out), d.digits, 10);
  mpz_set_ui(mpq_denref(out), 1);
  powerOfTen(scale.v, d.exponent - static_cast<long>(d.length) + 1);
  mpq_mul(out, out, scale.v);
}

// d moved by one in its last digit, either way, without a carry, to a text
// that still reads back as the double of magnitude `magnitude`; false when
// neither does.
bool otherOfAsMany(double magnitude, Decimal &d) {
  Interval interval(magnitude);
  for (int delta : {1, -1}) {
    Decimal c = d;
    char &last = c.digits[c.length - 1];
    if ((delta > 0 && last == '9') || (delta < 0 && last == (c.length == 1 ? '1' : '0')))
      continue;
    last = static_cast<char>(last + delta);
    Q v;
    decimalValue(c, v.v);
    if (interval.contains(v.v)) {
      d = c;
      return true;
    }
  }
  return false;
}

// show_f64 of a double, or the text a planted mutant writes in its place.
const idris_rt_str *showOf(double x) {
  if (exponentOf(bitsOf(x)) == 0 && finiteNonzero(x) && prop::planted(subnormalsAsZero))
    return idris_rt_str_show_f64(negativeBit(x) ? -0.0 : 0.0);
  const idris_rt_str *shown = idris_rt_str_show_f64(x);
  Decimal d;
  if (!finiteNonzero(x) || !readDecimal(idris_rt_str_bytes(shown), shown->bytes, d))
    return shown;
  long top = 9;
  bool changed = true;
  if (d.length > 1 && prop::planted(dropsDigit))
    d.digits[--d.length] = '\0';
  else if (prop::planted(seventeenDigits))
    printfDigits(x, 17, d);
  else if (prop::planted(sixteenDigits))
    printfDigits(x, 16, d);
  else if (d.exponent == 9 && prop::planted(scientificAt1e9))
    top = 8;
  else
    changed = prop::planted(otherNeighbour) && otherOfAsMany(fabs(x), d);
  if (!changed)
    return shown;
  idris_rt_str_release(shown);
  char text[64];
  size_t n = layout(d, text, top);
  return idris_rt_str_from_utf8(text, n);
}

// show_f64 of a double, released when it goes.
struct Shown {
  const idris_rt_str *string;
  explicit Shown(double x) : string(showOf(x)) {}
  ~Shown() { idris_rt_str_release(string); }
  Shown(const Shown &) = delete;
  Shown &operator=(const Shown &) = delete;
  const char *bytes() const { return idris_rt_str_bytes(string); }
  size_t length() const { return string->bytes; }
};

// A finite nonzero double as properties 1 to 3 read it: its text, read
// back; its magnitude X; the interval of the reals that round to it; and
// the text's value V.
struct Reading {
  double x;
  const Shown &shown;
  const Decimal &decimal;
  Interval interval;
  Q magnitude, value;
  Reading(double x, const Shown &shown, const Decimal &decimal)
      : x(x), shown(shown), decimal(decimal), interval(fabs(x)) {
    Q scale;
    mpq_set_d(magnitude.v, fabs(x));
    mpz_set_str(mpq_numref(value.v), decimal.digits, 10);
    mpz_set_ui(mpq_denref(value.v), 1);
    powerOfTen(scale.v, decimal.exponent - static_cast<long>(decimal.length) + 1);
    mpq_mul(value.v, value.v, scale.v);
  }
  // The decades the interval meets: floor(log10) of its ends, from the
  // estimate that the text's own exponent gives (exact comparison decides).
  long lowDecade() const { return decade(interval.lo.v, decimal.exponent); }
  long highDecade() const { return decade(interval.hi.v, decimal.exponent); }
  void explainText() const {
    prop::explain("%s: show_f64 wrote \"%.*s\"", Named(x).text, static_cast<int>(shown.length()), shown.bytes());
  }
};

// Properties 1 to 3 are stated of finite nonzero doubles, and `check`
// judges the Reading of one; a text that does not read is no double's
// text, and fails.
template <typename Check> bool ofDigits(double x, Check check) {
  if (!finiteNonzero(x))
    return true;
  Shown shown(x);
  Decimal decimal;
  if (!readDecimal(shown.bytes(), shown.length(), decimal)) {
    prop::explain("%s: show_f64 wrote \"%.*s\", not a decimal text", Named(x).text,
                  static_cast<int>(shown.length() < 64 ? shown.length() : 64), shown.bytes());
    return false;
  }
  return check(Reading(x, shown, decimal));
}

// q * s for s = 10^t, for an explanation: q's digits and `e` t.
void explainMultiple(const char *what, const mpq_t v, long t) {
  Q s, q;
  powerOfTen(s.v, t);
  mpq_div(q.v, v, s.v);
  char digits[400];
  if (mpz_sizeinbase(mpq_numref(q.v), 10) + 2 <= sizeof digits)
    prop::explain("%s %se%ld", what, mpz_get_str(digits, 10, mpq_numref(q.v)), t);
}

// 1. The text's value lies in the interval, with the double's sign.
bool readsBack(double x) {
  return ofDigits(x, [](const Reading &r) {
    bool holds = r.decimal.negative == negativeBit(r.x) && r.interval.contains(r.value.v);
    if (!holds) {
      r.explainText();
      prop::explain("its value does not round to the double");
    }
    return holds;
  });
}

// A text of at most n significant digits whose first stands in decade m or
// below is a multiple of 10^(m - n + 1) below 10^(m + 1) (one above it has
// a digit more), and the interval meets only the decades of its ends.
// `visit` is called with two such multiples from `first` up (a multiple of
// 10^(m - n + 1)), and the exponent of their last place; it returns false to
// stop.
template <typename Visit> bool candidates(mpq_t first, long m, long n, Visit visit) {
  Q s, top;
  powerOfTen(s.v, m - n + 1);
  powerOfTen(top.v, m + 1);
  for (int step = 0; step < 2 && mpq_cmp(first, top.v) < 0; ++step, mpq_add(first, first, s.v))
    if (!visit(first, m - n + 1))
      return false;
  return true;
}

// 2. No text of fewer digits reads back: none of at most len(D) - 1 digits
// lies in the interval, from its low end up. One digit is the fewest a text
// has.
bool noShorter(double x) {
  return ofDigits(x, [](const Reading &r) {
    auto k = static_cast<long>(r.decimal.length) - 1;
    if (k == 0)
      return true;
    for (long m : {r.lowDecade(), r.highDecade()}) {
      Q s, c;
      powerOfTen(s.v, m - k + 1);
      multipleAbove(c.v, r.interval.lo.v, s.v);
      bool none = candidates(c.v, m, k, [&](const mpq_t v, long place) {
        if (!r.interval.contains(v))
          return true;
        r.explainText();
        explainMultiple("a text of fewer digits reads back:", v, place);
        return false;
      });
      if (!none)
        return false;
    }
    return true;
  });
}

// 3. Of the texts with as many digits, none in the interval is nearer X,
// and of two as near the text's last digit is even: those nearest X are
// the ones just below and just above it.
bool nearestOfShortest(double x) {
  return ofDigits(x, [](const Reading &r) {
    bool even = (r.decimal.digits[r.decimal.length - 1] - '0') % 2 == 0;
    Q gap;
    mpq_sub(gap.v, r.value.v, r.magnitude.v);
    mpq_abs(gap.v, gap.v);
    auto n = static_cast<long>(r.decimal.length);
    for (long m : {r.lowDecade(), r.highDecade()}) {
      Q s, c;
      powerOfTen(s.v, m - n + 1);
      multipleBelow(c.v, r.magnitude.v, s.v);
      bool nearest = candidates(c.v, m, n, [&](const mpq_t v, long place) {
        if (!r.interval.contains(v) || mpq_equal(v, r.value.v))
          return true;
        Q other;
        mpq_sub(other.v, v, r.magnitude.v);
        mpq_abs(other.v, other.v);
        int order = mpq_cmp(other.v, gap.v);
        if (order > 0 || (order == 0 && even))
          return true;
        r.explainText();
        explainMultiple(order < 0 ? "a nearer text of as many digits:" : "as near, with an even last digit:", v,
                        place);
        return false;
      });
      if (!nearest)
        return false;
    }
    return true;
  });
}

// 4. The text is the runtime's: the fixed word of a NaN, an infinity or a
// zero; else the text written again from its sign, D and E, with the
// double's sign.
bool inLayout(double x) {
  Shown shown(x);
  if (!finiteNonzero(x)) {
    const char *word = wordFor(x);
    bool holds = shown.length() == strlen(word) && memcmp(shown.bytes(), word, shown.length()) == 0;
    if (!holds)
      prop::explain("%s: show_f64 wrote \"%.*s\", not \"%s\"", Named(x).text,
                    static_cast<int>(shown.length() < 64 ? shown.length() : 64), shown.bytes(), word);
    return holds;
  }
  Decimal d;
  char again[64];
  bool holds = readDecimal(shown.bytes(), shown.length(), d) && d.negative == negativeBit(x);
  size_t n = holds ? layout(d, again) : 0;
  holds = holds && n == shown.length() && memcmp(again, shown.bytes(), n) == 0;
  if (!holds)
    prop::explain("%s: show_f64 wrote \"%.*s\", where the layout writes \"%.*s\"", Named(x).text,
                  static_cast<int>(shown.length() < 64 ? shown.length() : 64), shown.bytes(), static_cast<int>(n),
                  again);
  return holds;
}

// 5. put_double writes show_f64's text, each followed here by a newline,
// and double_head is its first byte. A double's text is at most
// longestText bytes.
bool putsItsText(const double *xs, size_t count) {
  static char captured[prop::caseBytes * (longestText + 1)];
  size_t written = prop::captureStdout(
      [&] {
        for (size_t i = 0; i < count; ++i) {
          idris_rt_io_put_double(xs[i]);
          idris_rt_io_put_char('\n');
        }
      },
      captured, sizeof captured);
  size_t at = 0;
  for (size_t i = 0; i < count; ++i) {
    Shown shown(xs[i]);
    size_t n = shown.length();
    // The mutant's put_double, which writes 0.0 for -0.0, read against show_f64.
    const char *put = captured + at;
    if (bitsOf(xs[i]) == signBit && prop::planted(positiveZero) && at + 4 <= written)
      put = "0.0\n";
    bool holds = at + n + 1 <= written && at + n + 1 <= sizeof captured &&
                 memcmp(put, shown.bytes(), n) == 0 && put[n] == '\n' &&
                 idris_rt_double_head(xs[i]) == shown.bytes()[0];
    if (!holds) {
      prop::explain("%s: show_f64 wrote \"%.*s\"; put_double wrote \"%.*s\"; double_head gave %d", Named(xs[i]).text,
                    static_cast<int>(n), shown.bytes(),
                    static_cast<int>(written - at < n + 1 ? written - at : n + 1), captured + at,
                    idris_rt_double_head(xs[i]));
      return false;
    }
    at += n + 1;
  }
  return at == written;
}

// A text read by str_to_double, from a counted string of its bytes.
double readByRuntime(const char *text, size_t n) {
  const idris_rt_str *s = idris_rt_str_from_utf8(text, n);
  double x = idris_rt_str_to_double(s);
  idris_rt_str_release(s);
  return x;
}

// Whether two doubles are the same: bit for bit, or both NaNs.
bool same(double a, double b) { return bitsOf(a) == bitsOf(b) || (a != a && b != b); }

// 10. show_f64's text reads back through str_to_double, bit for bit.
bool roundTrips(double x) {
  Shown shown(x);
  double back = readByRuntime(shown.bytes(), shown.length());
  if (!same(back, x))
    prop::explain("%s: show_f64 wrote \"%.*s\", which str_to_double reads as %s", Named(x).text,
                  static_cast<int>(shown.length()), shown.bytes(), Named(back).text);
  return same(back, x);
}

// 11. to_int of a finite double: truncated toward zero (mpz_set_d is
// exact), then modulo 2^64, read as a signed integer.
bool truncates(double x) {
  if (exponentOf(bitsOf(x)) == exponentMask)
    return true;
  Z t;
  mpz_set_d(t.v, x);
  mpz_fdiv_r_2exp(t.v, t.v, 64);
  auto want = static_cast<int64_t>(static_cast<uint64_t>(mpz_get_ui(t.v)));
  int64_t got = idris_rt_to_int(x);
  if (fabs(x) >= 0x1p63 && prop::planted(saturates))
    got = INT64_MIN;
  if (got != want)
    prop::explain("%s: to_int gave %lld, not %lld", Named(x).text, static_cast<long long>(got),
                  static_cast<long long>(want));
  return got == want;
}


// The families a double is drawn from, simplest first; each gives a
// magnitude, and drawDouble its sign. Families 1 to 6 are the
// predecessor's patterns (double-print's fuzz.c).
double nearAnchor(FuzzedDataProvider &p, const double *anchors, size_t count) {
  double x = anchors[p.ConsumeIntegralInRange<size_t>(0, count - 1)];
  // Within 4 steps either way: the doubles on both sides of the anchor,
  // and of the boundary between two of them.
  unsigned steps = p.ConsumeIntegralInRange<unsigned>(0, 4);
  double toward = p.ConsumeBool() ? INFINITY : 0.0;
  for (unsigned k = 0; k < steps; ++k)
    x = nextafter(x, toward);
  return x;
}
struct DoubleFamily {
  const char *name;
  double (*draw)(FuzzedDataProvider &);
};
constexpr DoubleFamily doubleFamilies[] = {
    // Integers in [0, 1000] and eighths in [0, 8); 0.0 the simplest.
    {"simple",
     [](FuzzedDataProvider &p) {
       return p.ConsumeBool() ? p.ConsumeIntegralInRange<int>(0, 63) / 8.0
                              : static_cast<double>(p.ConsumeIntegralInRange<int>(0, 1000));
     }},
    // Any bits: NaNs and infinities too.
    {"any bits", [](FuzzedDataProvider &p) { return doubleOf(p.ConsumeIntegral<uint64_t>() & ~signBit); }},
    // Exponents near 1.0's (1023): about 15 decades either side.
    {"near one",
     [](FuzzedDataProvider &p) {
       uint64_t exponent = p.ConsumeIntegralInRange<uint64_t>(973, 1072);
       return doubleOf(exponent << significandBits | (p.ConsumeIntegral<uint64_t>() & significandMask));
     }},
    // Subnormals, of every width.
    {"subnormal",
     [](FuzzedDataProvider &p) {
       uint64_t significand = p.ConsumeIntegral<uint64_t>() & significandMask;
       return doubleOf(significand >> p.ConsumeIntegralInRange<unsigned>(0, significandBits - 1));
     }},
    // An odd m of 1 to 53 bits times 2^-j, j in [1, 1074]: exact, and its
    // decimal expansion ends in a 5, where the shortest digits may tie.
    {"ends in 5",
     [](FuzzedDataProvider &p) {
       unsigned bits = p.ConsumeIntegralInRange<unsigned>(1, significandBits + 1);
       uint64_t m = p.ConsumeIntegral<uint64_t>() >> (64 - bits) | 1;
       return ldexp(static_cast<double>(m), -p.ConsumeIntegralInRange<int>(1, 1074));
     }},
    // t + 0.25 for 2^50 <= t < 2^51: exact, and a tie at 17 digits.
    {"a tie at 17 digits",
     [](FuzzedDataProvider &p) {
       uint64_t t = (uint64_t{1} << 50) + p.ConsumeIntegralInRange<uint64_t>(0, (uint64_t{1} << 50) - 1);
       return static_cast<double>(t) + 0.25;
     }},
    // (10D + 5) * 10^k = (10D + 5) * 5^k * 2^k for D < 10^8, k up to a drawn
    // p < 23, while (10D + 5) * 5^k stays below 2^53, so it is exact.
    {"(10D + 5) * 10^p",
     [](FuzzedDataProvider &p) {
       uint64_t m = 10 * p.ConsumeIntegralInRange<uint64_t>(0, 99999999) + 5;
       int most = p.ConsumeIntegralInRange<int>(0, 22);
       int k = 0;
       for (; k < most && m * 5 < uint64_t{1} << (significandBits + 1); ++k)
         m *= 5;
       return ldexp(static_cast<double>(m), k);
     }},
    // Where the layout changes (1e-3, 1e10, 1e21) and each power of ten
    // from 1e-5 to 1e12.
    {"layout edges",
     [](FuzzedDataProvider &p) {
       constexpr double anchors[] = {1e-3, 1e10, 1e21, 1e-5, 1e-4, 1e-2, 1e-1, 1e0, 1e1, 1e2,
                                     1e3,  1e4,  1e5,  1e6,  1e7,  1e8,  1e9,  1e11, 1e12};
       return nearAnchor(p, anchors, sizeof anchors / sizeof anchors[0]);
     }},
    // The smallest subnormal, the largest subnormal, the smallest normal and
    // the largest finite.
    {"range edges",
     [](FuzzedDataProvider &p) {
       const double anchors[] = {doubleOf(1), doubleOf(significandMask), doubleOf(significandMask + 1),
                                 doubleOf((exponentMask - 1) << significandBits | significandMask)};
       return nearAnchor(p, anchors, sizeof anchors / sizeof anchors[0]);
     }},
    // The doubles IEEE 754 spells as words: a zero, an infinity, and NaNs,
    // quiet and signalling, of the least and the most payload; drawDouble
    // gives each its sign, so -0.0, -inf and the negative NaNs too.
    {"words",
     [](FuzzedDataProvider &p) {
       constexpr uint64_t anchors[] = {0, exponentMask << significandBits, 0x7FF8000000000000u,
                                       0x7FF0000000000001u, 0x7FF4000000000000u, 0x7FFFFFFFFFFFFFFFu};
       return doubleOf(p.PickValueInArray(anchors));
     }},
    // Where a word stops holding a double's integer: 2^52 and 2^53, past
    // which the doubles skip integers; 2^62, the small range's end; 2^63 and
    // 2^64, the int64 and uint64 ends, where to_int wraps; 2^116 and 2^117,
    // past which no bit of the integer is below 2^64.
    {"word edges",
     [](FuzzedDataProvider &p) {
       constexpr double anchors[] = {0x1p52, 0x1p53, 0x1p62, 0x1p63, 0x1p64, 0x1p116, 0x1p117};
       return nearAnchor(p, anchors, sizeof anchors / sizeof anchors[0]);
     }},
};
constexpr unsigned doubleFamilyCount = sizeof doubleFamilies / sizeof doubleFamilies[0];

double drawDouble(FuzzedDataProvider &p, uint64_t mask, prop::Tally &tally) {
  bool negative = p.ConsumeBool();
  const DoubleFamily &family = doubleFamilies[prop::pick(p, mask)];
  tally.classify(family.name);
  return doubleOf(bitsOf(family.draw(p)) | (negative ? signBit : 0));
}

// A case's doubles: the families swarmed, then doubles of them until the
// case's bytes run out (each draws at least its sign's byte). Returns how
// many, at least one.
size_t drawDoubles(FuzzedDataProvider &p, prop::Tally &tally, double *out) {
  uint64_t mask = prop::swarm(p, doubleFamilyCount);
  size_t n = 0;
  do
    out[n++] = drawDouble(p, mask, tally);
  while (p.remaining_bytes() > 0 && n < prop::caseBytes);
  return n;
}

template <typename Check> bool eachDouble(FuzzedDataProvider &p, prop::Tally &tally, Check check) {
  double xs[prop::caseBytes];
  size_t n = drawDoubles(p, tally, xs);
  for (size_t i = 0; i < n; ++i)
    if (!check(xs[i]))
      return false;
  return true;
}

// A sign as a text may write it: none, `+` or `-`.
char drawSign(FuzzedDataProvider &p) {
  constexpr char signs[] = {'\0', '+', '-'};
  return p.PickValueInArray(signs);
}

// The room of a text property 6 writes: the longest is the midpoint of a
// subnormal with a 1 appended, a sign, `0.`, then its 1075 fraction digits
// (the scale of its last bit, 2^-1075) and the 1.
constexpr size_t decimalRoom = 1 + 2 + 1075 + 1 + 1;

// A text in the grammar str_to_double and strtod share, and its exact
// value: the sign, then digits * 10^scale.
struct DecimalText {
  char text[decimalRoom];
  size_t length = 0;
  char digits[decimalRoom];
  size_t digitCount = 0;
  long scale = 0;
  bool negative = false;
  void put(char c) { text[length++] = c; }
  void digit(char c) {
    put(c);
    digits[digitCount++] = c;
  }
  void sign(char s) {
    negative = s == '-';
    if (s != '\0')
      put(s);
  }
  void end() {
    text[length] = '\0';
    digits[digitCount] = '\0';
  }
};

// A run of 1 to `most` digits.
void digitRun(FuzzedDataProvider &p, DecimalText &t, size_t most) {
  size_t n = p.ConsumeIntegralInRange<size_t>(1, most);
  for (size_t k = 0; k < n; ++k)
    t.digit(p.ConsumeIntegralInRange<char>('0', '9'));
}
// Up to 40 digits: past 17, the most a double's shortest text needs, and
// past 19, fast_float's fast path.
constexpr size_t mostDigits = 40;
// A point and a fraction: up to half of the digits on each side.
void pointed(FuzzedDataProvider &p, DecimalText &t) {
  digitRun(p, t, mostDigits / 2);
  t.put('.');
  size_t before = t.digitCount;
  digitRun(p, t, mostDigits / 2);
  t.scale -= static_cast<long>(t.digitCount - before);
}
// `e`, a sign and a magnitude up to 400: past 308 and -324, the decimal
// exponents doubles reach.
void exponent(FuzzedDataProvider &p, DecimalText &t) {
  t.put('e');
  char s = drawSign(p);
  if (s != '\0')
    t.put(s);
  long e = p.ConsumeIntegralInRange<long>(0, 400);
  t.length += static_cast<size_t>(snprintf(t.text + t.length, decimalRoom - t.length, "%ld", e));
  t.scale += s == '-' ? -e : e;
}
// The exact decimal of the midpoint between a positive finite double
// y = m * 2^e and the one above it, y + 2^e: (2m + 1) * 2^-j with j = 1 - e,
// written with f = max(j, 1) fraction digits as
// (2m + 1) * 2^(f - j) * 5^f * 10^-f; then with `delta` added to its digits
// as an integer of last place 10^-f (`appended` adds a place first).
void midpoint(FuzzedDataProvider &p, DecimalText &t, bool appended, long delta) {
  uint64_t field = p.ConsumeIntegralInRange<uint64_t>(0, exponentMask - 1);
  Binary y = binaryOf(doubleOf(field << significandBits | (p.ConsumeIntegral<uint64_t>() & significandMask)));
  uint64_t m = y.significand;
  long j = 1 - y.scale;
  long f = j > 1 ? j : 1;
  Z digits, five;
  mpz_set_ui(digits.v, 2 * m + 1);
  mpz_mul_2exp(digits.v, digits.v, static_cast<mp_bitcnt_t>(f - j));
  mpz_ui_pow_ui(five.v, 5, static_cast<unsigned long>(f));
  mpz_mul(digits.v, digits.v, five.v);
  if (appended) {
    mpz_mul_ui(digits.v, digits.v, 10);
    ++f;
  }
  if (delta >= 0)
    mpz_add_ui(digits.v, digits.v, static_cast<unsigned long>(delta));
  else
    mpz_sub_ui(digits.v, digits.v, static_cast<unsigned long>(-delta));
  char text[decimalRoom];
  mpz_get_str(text, 10, digits.v);
  auto n = static_cast<long>(strlen(text));
  // The digits, after zeros enough for one to stand before the point, with
  // the point before the last f.
  long total = n > f ? n : f + 1;
  for (long k = 0; k < total; ++k) {
    if (k == total - f)
      t.put('.');
    t.digit(k < total - n ? '0' : text[k - (total - n)]);
  }
  t.scale = -f;
}

// Property 6's texts, simplest first: the three forms of a decimal literal,
// which both grammars read the same way (never `E`, hexadecimal floats,
// spaces or words, where they differ; digits alone are an integer literal,
// property 7's, whose zero has no sign), and a midpoint between two adjacent doubles as it is, a hair
// above it (a 1 appended) and a hair below (its last digit lowered by one).
struct TextFamily {
  const char *name;
  void (*write)(FuzzedDataProvider &, DecimalText &);
};
constexpr TextFamily textFamilies[] = {
    {"a point", [](FuzzedDataProvider &p, DecimalText &t) { pointed(p, t); }},
    {"a point and an exponent",
     [](FuzzedDataProvider &p, DecimalText &t) {
       pointed(p, t);
       exponent(p, t);
     }},
    {"an exponent",
     [](FuzzedDataProvider &p, DecimalText &t) {
       digitRun(p, t, mostDigits);
       exponent(p, t);
     }},
    {"a midpoint", [](FuzzedDataProvider &p, DecimalText &t) { midpoint(p, t, false, 0); }},
    {"a midpoint and a 1", [](FuzzedDataProvider &p, DecimalText &t) { midpoint(p, t, true, 1); }},
    {"a midpoint less one", [](FuzzedDataProvider &p, DecimalText &t) { midpoint(p, t, false, -1); }},
};
constexpr unsigned textFamilyCount = sizeof textFamilies / sizeof textFamilies[0];

// Whether the exact value of t rounds to r: with r's sign, in r's interval
// when r is finite, past the largest finite's interval when r is infinite.
bool roundsTo(const DecimalText &t, double r) {
  Q v, scale;
  mpz_set_str(mpq_numref(v.v), t.digits, 10);
  mpz_set_ui(mpq_denref(v.v), 1);
  powerOfTen(scale.v, t.scale);
  mpq_mul(v.v, v.v, scale.v);
  if (t.negative != negativeBit(r))
    return false;
  if (exponentOf(bitsOf(r)) == exponentMask) {
    Interval largest(doubleOf((exponentMask - 1) << significandBits | significandMask));
    return mpq_cmp(v.v, largest.hi.v) >= 0;
  }
  return Interval(fabs(r)).contains(v.v);
}

// 6. str_to_double reads the text as strtod does.
bool readsAsStrtod(const DecimalText &t) {
  double want = strtod(t.text, nullptr);
  double got = readByRuntime(t.text, t.length);
  // The mutant's reader: each digit after the 19th significant one a 0.
  char cut[decimalRoom];
  memcpy(cut, t.text, t.length + 1);
  size_t significant = 0;
  bool exponentPart = false;
  for (size_t k = 0; k < t.length; ++k) {
    exponentPart |= cut[k] == 'e';
    if (exponentPart || !isDigit(cut[k]) || (significant == 0 && cut[k] == '0'))
      continue;
    if (++significant > 19)
      cut[k] = '0';
  }
  if (significant > 19 && prop::planted(truncatesAt19))
    got = strtod(cut, nullptr);
  if (bitsOf(got) != bitsOf(want)) {
    prop::explain("\"%.200s\"%s", t.text, t.length > 200 ? "..." : "");
    prop::explain("strtod: %s, which the text's value %s", Named(want).text,
                  roundsTo(t, want) ? "rounds to" : "does not round to");
    prop::explain("str_to_double: %s, which the text's value %s", Named(got).text,
                  roundsTo(t, got) ? "rounds to" : "does not round to");
  }
  return bitsOf(got) == bitsOf(want);
}

// The integer literals property 7 reads, by magnitude, simplest first:
// any below 2^64; within 4 of 2^53, where doubles stop holding every
// integer; 2^k +- 1 for k below 1100, past 2^1024, so that an overflow
// reads as an infinity.
constexpr long largestPower = 1100;
struct MagnitudeFamily {
  const char *name;
  void (*draw)(FuzzedDataProvider &, mpz_t);
};
constexpr MagnitudeFamily magnitudeFamilies[] = {
    {"below 2^64", [](FuzzedDataProvider &p, mpz_t v) { mpz_set_ui(v, p.ConsumeIntegral<uint64_t>()); }},
    {"near 2^53",
     [](FuzzedDataProvider &p, mpz_t v) {
       mpz_set_ui(v, (uint64_t{1} << (significandBits + 1)) - 4 + p.ConsumeIntegralInRange<uint64_t>(0, 8));
     }},
    {"2^k +- 1",
     [](FuzzedDataProvider &p, mpz_t v) {
       mpz_set_ui(v, 0);
       mpz_setbit(v, static_cast<mp_bitcnt_t>(p.ConsumeIntegralInRange<long>(0, largestPower - 1)));
       if (p.ConsumeBool())
         mpz_sub_ui(v, v, 1);
       else
         mpz_add_ui(v, v, 1);
     }},
};
constexpr unsigned magnitudeFamilyCount = sizeof magnitudeFamilies / sizeof magnitudeFamilies[0];

// An integer literal's prefix and base, decimal the simplest.
struct Base {
  const char *prefix;
  int base;
};
constexpr Base bases[] = {{"", 10}, {"0b", 2}, {"0o", 8}, {"0x", 16}, {"0X", 16}};

// The room of a literal: a sign, a prefix, the binary digits of 2^1099 + 1
// with an underscore between every two, and the end.
constexpr size_t literalRoom = 1 + 2 + 2 * static_cast<size_t>(largestPower) + 1;

// An integer literal as the runtime's grammar writes one, and the decimal
// text of its value, signed, which strtod reads to the nearest double, ties
// to even, an infinity past the largest. The value is an integer, so -0 is
// 0, and its text has no sign.
struct IntegerLiteral {
  char text[literalRoom];
  size_t length = 0;
  char decimal[literalRoom];
};
void drawLiteral(FuzzedDataProvider &p, uint64_t mask, prop::Tally &tally, IntegerLiteral &out) {
  const MagnitudeFamily &family = magnitudeFamilies[prop::pick(p, mask)];
  tally.classify(family.name);
  Z v;
  family.draw(p, v.v);
  const Base &base = bases[p.ConsumeIntegralInRange<size_t>(0, sizeof bases / sizeof bases[0] - 1)];
  char sign = drawSign(p);
  char digits[literalRoom];
  mpz_get_str(digits, base.base, v.v);
  size_t n = strlen(digits);
  // Underscores between groups of a drawn width, counted from the last
  // digit (1_000_000); width 0, the simplest, puts none.
  size_t width = p.ConsumeIntegralInRange<size_t>(0, n - 1);
  out.length = 0;
  if (sign != '\0')
    out.text[out.length++] = sign;
  for (const char *c = base.prefix; *c != '\0'; ++c)
    out.text[out.length++] = *c;
  for (size_t k = 0; k < n; ++k) {
    if (width > 0 && k > 0 && (n - k) % width == 0)
      out.text[out.length++] = '_';
    bool upper = digits[k] >= 'a' && p.ConsumeBool();
    out.text[out.length++] = upper ? static_cast<char>(digits[k] - 'a' + 'A') : digits[k];
  }
  out.text[out.length] = '\0';
  if (sign == '-')
    mpz_neg(v.v, v.v);
  mpz_get_str(out.decimal, 10, v.v);
}
// strtod of the literal's value.
double literalWant(const IntegerLiteral &l) { return strtod(l.decimal, nullptr); }

// The words IEEE 754 spells, read in any case with any sign.
struct Word {
  const char *text;
  bool nan;
};
constexpr Word words[] = {{"inf", false}, {"infinity", false}, {"nan", true}};

// The named malformed texts, one family each; each `#` is a drawn digit.
// Some have none, so a case picks a family per text from all of them,
// which draws a byte each time, until its bytes run out.
struct Malformed {
  const char *name;
  const char *pattern;
};
constexpr Malformed malformed[] = {
    {".5", ".#"},       {"5.", "#."},     {"1.e3", "#.e#"},      {"1E3", "#E#"},   {"1.5e", "#.#e"},
    {"1_000.5", "#_#.#"}, {"1d3", "#d#"},   {"1/2", "#/#"},        {" 1", " #"},     {"1 ", "# "},
    {"0x1p3", "0x#p#"}, {"+inf.0", "+inf.0"}, {"nan(1)", "nan(#)"}, {"the empty string", ""},
};

// Box 12: every exponent field, each with these significands and both
// signs, so 2048 * 9 * 2 doubles; one field's are checked together, and
// put_double writes them in one capture.
constexpr uint64_t edgeSignificands[] = {0,
                                         1,
                                         2,
                                         3,
                                         (uint64_t{1} << 51) - 1,
                                         uint64_t{1} << 51,
                                         (uint64_t{1} << 51) + 1,
                                         (uint64_t{1} << 52) - 2,
                                         (uint64_t{1} << 52) - 1};
constexpr size_t edgeCount = sizeof edgeSignificands / sizeof edgeSignificands[0];
// Properties 1 to 5 and 10 of each double of an exponent field.
bool everyShowProperty(uint64_t field) {
  double xs[2 * edgeCount];
  size_t n = 0;
  for (uint64_t sign : {uint64_t{0}, signBit})
    for (uint64_t significand : edgeSignificands)
      xs[n++] = doubleOf(sign | field << significandBits | significand);
  for (double x : xs)
    if (!(readsBack(x) && noShorter(x) && nearestOfShortest(x) && inLayout(x) && roundTrips(x)))
      return false;
  return putsItsText(xs, n);
}

// 13. show_f64 returns one new string (count 1, one more live cell; a text
// is never empty) that, released, leaves the live cells as they were; and
// str_to_double leaves its counted argument's count and the live cells as
// they were.
bool showOwned(double x) {
  uint64_t before = idris_rt_live_cells();
  const idris_rt_str *s = idris_rt_str_show_f64(x);
  uint32_t count = s->header.count + (prop::planted(extraReference) ? 1 : 0);
  bool owned = count == 1 && idris_rt_live_cells() == before + 1;
  idris_rt_str_release(s);
  bool released = idris_rt_live_cells() == before;
  if (!(owned && released))
    prop::explain("%s: show_f64's result has count %u, and %s after its release", Named(x).text, count,
                  released ? "no cell is left" : "a cell is left");
  return owned && released;
}
bool readBorrows(const char *text, size_t n) {
  const idris_rt_str *s = idris_rt_str_from_utf8(text, n);
  uint32_t count = s->header.count;
  uint64_t before = idris_rt_live_cells();
  idris_rt_str_to_double(s);
  bool holds = s->header.count == count && idris_rt_live_cells() == before;
  if (!holds)
    prop::explain("str_to_double of \"%.*s\": count %u became %u, live cells %llu became %llu",
                  static_cast<int>(n < 64 ? n : 64), text, count, s->header.count,
                  static_cast<unsigned long long>(before), static_cast<unsigned long long>(idris_rt_live_cells()));
  idris_rt_str_release(s);
  return holds;
}

} // namespace

int main(int argc, char **argv) {
  prop::Run run(argc, argv);

  run.property("show_f64: reads back as the double", dropsDigit,
               [](FuzzedDataProvider &p, prop::Tally &tally) { return eachDouble(p, tally, readsBack); });
  run.property("show_f64: no shorter text reads back", seventeenDigits,
               [](FuzzedDataProvider &p, prop::Tally &tally) { return eachDouble(p, tally, noShorter); });
  run.property("show_f64: the nearest of the shortest, ties to the even digit", otherNeighbour,
               [](FuzzedDataProvider &p, prop::Tally &tally) { return eachDouble(p, tally, nearestOfShortest); });
  run.property("show_f64: the runtime's layout", scientificAt1e9,
               [](FuzzedDataProvider &p, prop::Tally &tally) { return eachDouble(p, tally, inLayout); });
  run.property("put_double, double_head: show_f64's text", positiveZero, [](FuzzedDataProvider &p, prop::Tally &tally) {
    double xs[prop::caseBytes];
    size_t n = drawDoubles(p, tally, xs);
    return putsItsText(xs, n);
  });

  run.property("str_to_double: strtod's double for every decimal text", truncatesAt19,
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 uint64_t mask = prop::swarm(p, textFamilyCount);
                 do {
                   const TextFamily &family = textFamilies[prop::pick(p, mask)];
                   tally.classify(family.name);
                   DecimalText t;
                   t.sign(drawSign(p));
                   family.write(p, t);
                   t.end();
                   if (!readsAsStrtod(t))
                     return false;
                 } while (p.remaining_bytes() > 0);
                 return true;
               });

  run.property("str_to_double: integer literals of every base read as the nearest double", literalModulo,
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 uint64_t mask = prop::swarm(p, magnitudeFamilyCount);
                 do {
                   IntegerLiteral l;
                   drawLiteral(p, mask, tally, l);
                   double want = literalWant(l);
                   double got = readByRuntime(l.text, l.length);
                   if (prop::planted(literalModulo)) {
                     Z v;
                     mpz_set_str(v.v, l.decimal + 1, 10);
                     mpz_fdiv_r_2exp(v.v, v.v, 64);
                     double low = static_cast<double>(static_cast<uint64_t>(mpz_get_ui(v.v)));
                     got = l.text[0] == '-' ? -low : low;
                   }
                   if (bitsOf(got) != bitsOf(want)) {
                     prop::explain("\"%.200s\": str_to_double %s, strtod of its value %s", l.text, Named(got).text,
                                   Named(want).text);
                     return false;
                   }
                 } while (p.remaining_bytes() > 0);
                 return true;
               });

  run.property("str_to_double: inf, infinity and nan in any case, signed", lowercaseWords,
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 do {
                   const Word &word = p.PickValueInArray(words);
                   tally.classify(word.text);
                   char sign = drawSign(p);
                   char text[16];
                   size_t n = 0;
                   if (sign != '\0')
                     text[n++] = sign;
                   bool upper = false;
                   for (const char *c = word.text; *c != '\0'; ++c) {
                     bool letter = p.ConsumeBool();
                     upper |= letter;
                     text[n++] = letter ? static_cast<char>(*c - 'a' + 'A') : *c;
                   }
                   double got = readByRuntime(text, n);
                   if (upper && prop::planted(lowercaseWords))
                     got = 0.0;
                   double infinity = sign == '-' ? -INFINITY : INFINITY;
                   bool holds = word.nan ? got != got : bitsOf(got) == bitsOf(infinity);
                   if (!holds) {
                     prop::explain("\"%.*s\": str_to_double %s", static_cast<int>(n), text, Named(got).text);
                     return false;
                   }
                 } while (p.remaining_bytes() > 0);
                 return true;
               });

  run.property("str_to_double: every named malformed text reads as 0.0", leadingPoint,
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 do {
                   const Malformed &family = p.PickValueInArray(malformed);
                   tally.classify(family.name);
                   char text[16];
                   size_t n = 0;
                   for (const char *c = family.pattern; *c != '\0'; ++c)
                     text[n++] = *c == '#' ? p.ConsumeIntegralInRange<char>('0', '9') : *c;
                   double got = readByRuntime(text, n);
                   if (n > 0 && text[0] == '.' && prop::planted(leadingPoint)) {
                     text[n] = '\0';
                     got = strtod(text, nullptr);
                   }
                   if (bitsOf(got) != 0) {
                     prop::explain("\"%.*s\": str_to_double %s, not 0.0", static_cast<int>(n), text, Named(got).text);
                     return false;
                   }
                 } while (p.remaining_bytes() > 0);
                 return true;
               });

  run.property("round trip: str_to_double of show_f64", sixteenDigits,
               [](FuzzedDataProvider &p, prop::Tally &tally) { return eachDouble(p, tally, roundTrips); });
  run.property("to_int: truncated toward zero, modulo 2^64", saturates,
               [](FuzzedDataProvider &p, prop::Tally &tally) { return eachDouble(p, tally, truncates); });

  run.box("box: every exponent with the edge significands", exponentMask + 1, subnormalsAsZero, everyShowProperty);

  run.property("every operation borrows its argument and returns one owned result", extraReference,
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 uint64_t mask = prop::swarm(p, doubleFamilyCount);
                 uint64_t literals = prop::swarm(p, magnitudeFamilyCount);
                 do {
                   double x = drawDouble(p, mask, tally);
                   Shown shown(x);
                   IntegerLiteral l;
                   drawLiteral(p, literals, tally, l);
                   if (!(showOwned(x) && readBorrows(shown.bytes(), shown.length()) && readBorrows(l.text, l.length)))
                     return false;
                 } while (p.remaining_bytes() > 0);
                 return true;
               });

  return run.finish();
}
