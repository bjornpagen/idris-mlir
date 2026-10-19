// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's integer text held to its meaning in the runtime: show and
// put against snprintf's decimal text, big_show against GMP's, and `cast`
// from String to an integer against its grammar's prose: every literal the
// grammar generates reads as its value, every named malformed one as 0, and
// every short string over the literal alphabet as a recognizer written from
// the prose says. Then the round trips, and ownership.
#include "bigmodel.h"
#include "idris_rt.h"
#include "prop.h"

#include <gmp.h>
#include <inttypes.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

namespace {

using bigmodel::explainValues;
using bigmodel::low64;
using bigmodel::Operand;
using bigmodel::Result;
using bigmodel::Z;

// A string the test owns, an operation's result or one made from text,
// released when it goes.
class Text {
public:
  explicit Text(const idris_rt_str *s) : s_(s) {}
  ~Text() { idris_rt_str_release(s_); }
  Text(const Text &) = delete;
  Text &operator=(const Text &) = delete;
  const idris_rt_str *get() const { return s_; }

private:
  const idris_rt_str *s_;
};

// The decimal text of a word, a sign and 19 digits or 20 digits, and its NUL.
constexpr size_t wordText = 22;

// s is exactly the n bytes at want, all ASCII, so its scalars are its bytes.
bool textIs(const char *what, const idris_rt_str *s, const char *want, size_t n) {
  bool ok = s->bytes == n && s->scalars == n && memcmp(idris_rt_str_bytes(s), want, n) == 0;
  if (!ok)
    prop::explain("%s gives \"%.*s\" of %llu bytes and %llu scalars, where \"%.*s\" is expected", what,
                  static_cast<int>(s->bytes < 200 ? s->bytes : 200), idris_rt_str_bytes(s),
                  static_cast<unsigned long long>(s->bytes), static_cast<unsigned long long>(s->scalars),
                  static_cast<int>(n), want);
  return ok;
}

// The words a property draws, simplest first: 0 and +-1; the edges of int64
// and uint64, 2^63 - 1, 2^63 and 2^64 - 1, and one either side; +-10^k and
// one either side, where the decimal text gains a digit; and any word.
constexpr unsigned wordFamilies = 4;
constexpr const char *wordNames[wordFamilies] = {"0 and +-1", "the words' edges", "powers of ten", "any word"};
uint64_t drawWord(FuzzedDataProvider &p, unsigned family) {
  static constexpr uint64_t edges[] = {uint64_t{INT64_MAX}, uint64_t{1} << 63, UINT64_MAX};
  static constexpr uint64_t offByOne[] = {0, 1, UINT64_MAX};
  uint64_t word;
  switch (family) {
  case 0:
    word = p.PickValueInArray(offByOne);
    break;
  case 1:
    word = p.PickValueInArray(edges) + p.PickValueInArray(offByOne);
    break;
  case 2: {
    // 10^19 is the largest power of ten a word holds.
    uint64_t power = 1;
    for (unsigned k = p.ConsumeIntegralInRange<unsigned>(0, 19); k > 0; --k)
      power *= 10;
    word = power + p.PickValueInArray(offByOne);
    word = p.ConsumeBool() ? 0 - word : word;
    break;
  }
  default:
    word = p.ConsumeIntegral<uint64_t>();
    break;
  }
  prop::explain("word = %#llx", static_cast<unsigned long long>(word));
  return word;
}

// 1. show_s, show_u, int_head_s and int_head_u: snprintf's decimal text of
// the word, signed and unsigned, and its first character.
bool shown(uint64_t word) {
  auto x = static_cast<int64_t>(word);
  char signedText[wordText], unsignedText[wordText];
  auto ns = static_cast<size_t>(snprintf(signedText, sizeof signedText, "%" PRId64, x));
  auto nu = static_cast<size_t>(snprintf(unsignedText, sizeof unsignedText, "%" PRIu64, word));
  Text s(idris_rt_str_show_s(x)), u(idris_rt_str_show_u(word));
  bool ok = textIs("show_s", s.get(), signedText, ns);
  ok &= textIs("show_u", u.get(), unsignedText, nu);
  int32_t headS = idris_rt_int_head_s(x), headU = idris_rt_int_head_u(word);
  if (headS != signedText[0] || headU != unsignedText[0]) {
    prop::explain("int_head_s gives %d and int_head_u %d, where the texts start with %d and %d", headS, headU,
                  signedText[0], unsignedText[0]);
    ok = false;
  }
  return ok;
}

// The values a case of put() writes.
constexpr unsigned putValues = 16;

// 2. put_int_s and put_int_u write on standard output what snprintf writes.
bool put(FuzzedDataProvider &p, prop::Tally &tally) {
  uint64_t mask = prop::swarm(p, wordFamilies);
  unsigned count = p.ConsumeIntegralInRange<unsigned>(1, putValues);
  uint64_t words[putValues];
  char want[putValues * 2 * wordText];
  size_t used = 0;
  for (unsigned i = 0; i < count; ++i) {
    unsigned family = prop::pick(p, mask);
    words[i] = drawWord(p, family);
    used += static_cast<size_t>(snprintf(want + used, sizeof want - used, "%" PRId64 "\n%" PRIu64 "\n",
                                         static_cast<int64_t>(words[i]), words[i]));
    tally.classify(wordNames[family]);
  }
  char got[sizeof want];
  size_t written = prop::captureStdout(
      [&] {
        for (unsigned i = 0; i < count; ++i) {
          idris_rt_io_put_int_s(static_cast<int64_t>(words[i]));
          idris_rt_io_put_char('\n');
          idris_rt_io_put_int_u(words[i]);
          idris_rt_io_put_char('\n');
        }
      },
      got, sizeof got);
  bool ok = written == used && memcmp(got, want, used) == 0;
  if (!ok) {
    // The first line that differs, from its start to its end in each.
    size_t kept = written < sizeof got ? written : sizeof got, at = 0, start = 0;
    for (; at < kept && at < used && got[at] == want[at]; ++at)
      start = got[at] == '\n' ? at + 1 : start;
    auto lineOf = [](const char *text, size_t from, size_t end) {
      const void *newline = memchr(text + from, '\n', end - from);
      return static_cast<int>((newline != nullptr ? static_cast<const char *>(newline) : text + end) - (text + from));
    };
    prop::explain("put_int wrote %zu bytes, snprintf %zu; from byte %zu, \"%.*s\" where snprintf has \"%.*s\"",
                  written, used, start, lineOf(got, start, kept), got + start, lineOf(want, start, used),
                  want + start);
  }
  return ok;
}

// The longest decimal text of a big a property draws: a limb is below
// 10^20, so maxLimbs of them have at most 20 digits each; a sign and a NUL.
constexpr size_t bigText = 20 * bigmodel::maxLimbs + 2;

// 3. big_show writes GMP's decimal text of the value.
bool bigShown(const Operand &a) {
  char want[bigText];
  mpz_get_str(want, 10, a.value());
  Text s(idris_rt_big_show(a.word()));
  return textIs("big_show", s.get(), want, strlen(want));
}

// The bases an integer literal is written in: the prefix that says so, a
// name for the report, and characters outside the base for a malformed
// literal, those the next base up has, but for decimal, which leaves out
// b, o, x and X: after a leading 0 they would make a prefix.
struct Base {
  unsigned radix;
  const char *prefix;
  const char *name;
  const char *outside;
};
constexpr Base bases[] = {{10, "", "decimal", "acdef"},
                          {2, "0b", "0b", "23456789"},
                          {8, "0o", "0o", "89"},
                          {16, "0x", "0x", "gG"},
                          {16, "0X", "0X", "gG"}};
constexpr unsigned baseCount = sizeof bases / sizeof bases[0];
// The bases whose prefix letter has no upper case form: 0b and 0o.
constexpr unsigned lowerOnly[] = {1, 2};

// The longest text a literal is: a sign, a prefix, 3 leading zeros and
// the digits, at most 64 * maxLimbs in binary, an underscore between each
// two of those, then what a malformed family adds: under 16 bytes.
constexpr size_t literalRoom = 1 + 2 + 2 * (3 + 64 * bigmodel::maxLimbs) + 16;

// A literal's text, where its digits start (past its sign and prefix), and
// the integer it writes.
struct Literal {
  char text[literalRoom];
  size_t length = 0;
  size_t digits = 0;
  Z value;

  void put(char c) { text[length++] = c; }
  void put(const char *s) {
    for (; *s != '\0'; ++s)
      put(*s);
  }
  // c at `at`, the text after it moved along.
  void insert(size_t at, char c) {
    memmove(text + at + 1, text + at, length - at);
    text[at] = c;
    ++length;
  }
};

// The magnitudes a literal writes, simplest first: a big's, from bigmodel's
// families, then a word's.
constexpr unsigned magnitudeFamilies = bigmodel::families + wordFamilies;
void drawMagnitude(FuzzedDataProvider &p, unsigned family, mpz_ptr out) {
  // The two sources of values, each with families of its own.
  if (family < bigmodel::families) {
    bigmodel::draw(p, family, out);
    mpz_abs(out, out);
  } else {
    mpz_set_ui(out, drawWord(p, family - bigmodel::families));
  }
}

// A literal the grammar generates, in `base`: an optional sign, `+` or `-`;
// the prefix; up to 3 leading zeros; the magnitude's digits, each hex digit
// in a drawn case; and an underscore at drawn places between two digits.
void generate(FuzzedDataProvider &p, uint64_t mask, const Base &base, Literal &out) {
  Z magnitude;
  drawMagnitude(p, prop::pick(p, mask), magnitude);
  static constexpr const char *signs[] = {"", "+", "-"};
  const char *sign = p.PickValueInArray(signs);
  char digits[3 + 64 * bigmodel::maxLimbs + 2] = "000";
  size_t zeros = p.ConsumeIntegralInRange<size_t>(0, 3);
  mpz_get_str(digits + zeros, static_cast<int>(base.radix), magnitude);
  out.length = 0;
  out.put(sign);
  out.put(base.prefix);
  out.digits = out.length;
  // Only a letter has a case.
  auto digit = [&](char c) { out.put(c >= 'a' && p.ConsumeBool() ? static_cast<char>(c - 'a' + 'A') : c); };
  // The first digit, then each other one after a drawn underscore: an
  // underscore stands between two digits.
  digit(digits[0]);
  for (size_t i = 1; digits[i] != '\0'; ++i) {
    if (p.ConsumeBool())
      out.put('_');
    digit(digits[i]);
  }
  mpz_mul_si(out.value, magnitude, sign[0] == '-' ? -1 : 1);
}

// The n bytes at text read by both integer casts: big_from_str gives
// `value` exactly, canonical, and str_to_int its low 64 bits.
bool reads(const char *text, size_t n, mpz_srcptr value) {
  prop::explain("text \"%.*s\"", static_cast<int>(n), text);
  Text s(idris_rt_str_from_utf8(text, n));
  Result big(idris_rt_big_from_str(s.get()));
  int64_t wrapped = idris_rt_str_to_int(s.get());
  bool shaped = bigmodel::canonical(big.word());
  bool exact = mpz_cmp(big.value(), value) == 0;
  bool modular = static_cast<uint64_t>(wrapped) == low64(value);
  if (!shaped || !exact || !modular)
    explainValues("big_from_str gives %Zd and str_to_int %lld, where the value is %Zd", big.value(),
                  static_cast<long long>(wrapped), value);
  return shaped && exact && modular;
}

// The malformed literals, one family each, simplest first.
constexpr const char *malformedNames[] = {"empty",
                                          "a sign alone",
                                          "a leading underscore",
                                          "a trailing underscore",
                                          "two underscores",
                                          "0B or 0O",
                                          "a prefix with no digit",
                                          "a digit outside the base",
                                          "a decimal point",
                                          "an exponent",
                                          "a space before or after",
                                          "inf or nan"};
constexpr unsigned malformedFamilies = sizeof malformedNames / sizeof malformedNames[0];

// A base, drawn.
const Base &drawBase(FuzzedDataProvider &p) { return bases[p.ConsumeIntegralInRange<unsigned>(0, baseCount - 1)]; }

// A text no integer cast reads: a literal of the grammar, broken as
// `family` names.
void malformed(FuzzedDataProvider &p, uint64_t mask, unsigned family, Literal &out) {
  static constexpr const char *signs[] = {"+", "-"};
  static constexpr const char *prefixes[] = {"0b", "0o", "0x", "0X"};
  static constexpr const char *words[] = {"inf", "infinity", "nan"};
  out.length = 0;
  switch (family) {
  case 0:
    return;
  case 1:
    return out.put(p.PickValueInArray(signs));
  case 2:
    generate(p, mask, drawBase(p), out);
    return out.insert(out.digits, '_');
  case 3:
    generate(p, mask, drawBase(p), out);
    return out.put('_');
  case 4:
    // 1 is a digit of every base.
    generate(p, mask, drawBase(p), out);
    return out.put("__1");
  case 5:
    // 0b or 0o with its letter upper case.
    generate(p, mask, bases[p.PickValueInArray(lowerOnly)], out);
    out.text[out.digits - 1] = static_cast<char>(out.text[out.digits - 1] - 'a' + 'A');
    return;
  case 6:
    out.put(p.ConsumeBool() ? p.PickValueInArray(signs) : "");
    return out.put(p.PickValueInArray(prefixes));
  case 7: {
    const Base &base = drawBase(p);
    generate(p, mask, base, out);
    size_t at = p.ConsumeIntegralInRange<size_t>(out.digits, out.length);
    return out.insert(at, base.outside[p.ConsumeIntegralInRange<size_t>(0, strlen(base.outside) - 1)]);
  }
  case 8:
    generate(p, mask, bases[0], out);
    return out.put(".5");
  case 9: {
    static constexpr const char *exponents[] = {"e5", "e+5", "e-5"};
    generate(p, mask, bases[0], out);
    return out.put(p.PickValueInArray(exponents));
  }
  case 10:
    generate(p, mask, drawBase(p), out);
    return p.ConsumeBool() ? out.insert(0, ' ') : out.put(' ');
  default: {
    out.put(p.ConsumeBool() ? p.PickValueInArray(signs) : "");
    for (const char *w = p.PickValueInArray(words); *w != '\0'; ++w)
      out.put(p.ConsumeBool() ? static_cast<char>(*w - 'a' + 'A') : *w);
    return;
  }
  }
}

// The literal alphabet: digits of every base and those outside some, the
// prefixes' letters in both cases, the underscore, the signs, a point, an
// exponent's e and a space.
constexpr char alphabet[] = "01789afAFgxXbBoO_+-.e ";
constexpr uint64_t letters = sizeof alphabet - 1;
// Every string of at most 3 letters.
constexpr uint64_t shortStrings = 1 + letters + letters * letters + letters * letters * letters;

// The string of index i in shortlex order, by length then letter by
// letter: its length, its letters in out.
size_t shortString(uint64_t i, char *out) {
  size_t length = 0;
  for (uint64_t count = 1; i >= count; count *= letters) {
    i -= count;
    ++length;
  }
  for (size_t k = length; k > 0; --k) {
    out[k - 1] = alphabet[i % letters];
    i /= letters;
  }
  return length;
}

// What a character is as a digit of `radix`, or -1.
int digitOf(char c, unsigned radix) {
  int d = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'z' ? c - 'a' + 10 : c >= 'A' && c <= 'Z' ? c - 'A' + 10 : -1;
  return d >= 0 && static_cast<unsigned>(d) < radix ? d : -1;
}

// `cast` from String to an integer as the runtime's prose has it: the
// whole string an optional sign (+ or -), then decimal digit groups, or 0
// and one of b, o, x, X and digit groups of that base, a group being digits
// that single underscores separate, gives the integer it writes, by
// Horner's rule; any other string gives 0.
void castValue(const char *s, size_t n, mpz_ptr value) {
  static constexpr struct {
    char letter;
    unsigned radix;
  } prefixes[] = {{'b', 2}, {'o', 8}, {'x', 16}, {'X', 16}};
  size_t at = n > 0 && (s[0] == '+' || s[0] == '-');
  bool negative = at == 1 && s[0] == '-';
  unsigned radix = 10;
  for (const auto &prefix : prefixes)
    if (n - at >= 2 && s[at] == '0' && s[at + 1] == prefix.letter) {
      radix = prefix.radix;
      at += 2;
      break;
    }
  // What the text read last: nothing yet, a digit, or an underscore, which
  // a digit must come before and after.
  enum class Last { Nothing, Digit, Underscore } last = Last::Nothing;
  mpz_set_ui(value, 0);
  for (; at < n; ++at) {
    if (s[at] == '_' && last == Last::Digit) {
      last = Last::Underscore;
      continue;
    }
    int d = digitOf(s[at], radix);
    // A character no literal has there: no literal.
    if (d < 0)
      return mpz_set_ui(value, 0);
    mpz_mul_ui(value, value, radix);
    mpz_add_ui(value, value, static_cast<unsigned long>(d));
    last = Last::Digit;
  }
  // Ending on a digit is a literal; anything else is 0.
  mpz_mul_si(value, value, last != Last::Digit ? 0 : negative ? -1 : 1);
}

// The references a cell holds, a string or a large big; a small big is no
// cell, and holds none.
uint32_t referencesOf(const void *o) {
  if ((reinterpret_cast<uintptr_t>(o) & 1) != 0)
    return 0;
  idris_rt_header header;
  memcpy(&header, o, sizeof header);
  return header.count;
}

// What a call gives when its result is no object: an odd word, which owns
// nothing; and what it borrows when it borrows none.
const void *nothing() { return reinterpret_cast<const void *>(uintptr_t{1}); }

// One call, which borrows its operand and returns one owned result: the
// operand keeps its references while the result lives, and once the result
// is released the live cells are as before the call. No result here is
// its operand, whose type differs. A string and a big are released alike
// (idris_rt_dec).
template <typename Call> bool borrows(const char *name, const void *operand, Call call) {
  uint32_t before = referencesOf(operand);
  uint64_t live = idris_rt_live_cells();
  const void *result = call();
  uint32_t during = referencesOf(operand);
  idris_rt_dec(const_cast<void *>(result));
  uint64_t after = idris_rt_live_cells();
  bool ok = during == before && referencesOf(operand) == before && after == live;
  if (!ok)
    prop::explain("%s: its operand's references %u became %u, then %u; live cells %llu, then %llu", name, before,
                  during, referencesOf(operand), static_cast<unsigned long long>(live),
                  static_cast<unsigned long long>(after));
  return ok;
}

// A big as a pointer, the form the counting entry points take.
const void *asPointer(idris_rt_big b) { return reinterpret_cast<const void *>(b); }

} // namespace

int main(int argc, char **argv) {
  idris_rt_gmp_init();
  prop::Run run(argc, argv);

  run.property("show_s, show_u, int_head_s, int_head_u: snprintf's text", [](FuzzedDataProvider &p, prop::Tally &tally) {
    unsigned family = prop::pick(p, prop::swarm(p, wordFamilies));
    tally.classify(wordNames[family]);
    return shown(drawWord(p, family));
  });

  run.property("put_int_s, put_int_u: snprintf's text on standard output", put);

  run.property("big_show: GMP's decimal text", [](FuzzedDataProvider &p, prop::Tally &tally) {
    Z v;
    bigmodel::draw(p, prop::pick(p, prop::swarm(p, bigmodel::families)), v);
    explainValues("a = %#Zx", static_cast<mpz_srcptr>(v));
    Operand a(v);
    static constexpr const char *forms[] = {"large", "small"};
    tally.classify(forms[a.word() & 1]);
    return bigShown(a);
  });

  run.property("to_int, big_from_str: every literal the grammar generates reads as its value",
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 uint64_t mask = prop::swarm(p, magnitudeFamilies);
                 const Base &base = drawBase(p);
                 Literal literal;
                 generate(p, mask, base, literal);
                 tally.classify(base.name);
                 return reads(literal.text, literal.length, literal.value);
               });

  run.property("to_int, big_from_str: every named malformed literal reads as 0",
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 uint64_t mask = prop::swarm(p, magnitudeFamilies);
                 unsigned family = prop::pick(p, prop::swarm(p, malformedFamilies));
                 Literal literal;
                 malformed(p, mask, family, literal);
                 tally.classify(malformedNames[family]);
                 Z zero;
                 return reads(literal.text, literal.length, zero);
               });

  run.property("round trip: to_int of show_s, big_from_str of big_show", [](FuzzedDataProvider &p, prop::Tally &tally) {
    auto x = static_cast<int64_t>(drawWord(p, prop::pick(p, prop::swarm(p, wordFamilies))));
    Text s(idris_rt_str_show_s(x));
    int64_t back = idris_rt_str_to_int(s.get());
    bool ok = back == x;
    if (!ok)
      prop::explain("to_int of show_s gives %lld", static_cast<long long>(back));
    Z v;
    bigmodel::draw(p, prop::pick(p, prop::swarm(p, bigmodel::families)), v);
    explainValues("a = %#Zx", static_cast<mpz_srcptr>(v));
    Operand a(v);
    Text t(idris_rt_big_show(a.word()));
    Result r(idris_rt_big_from_str(t.get()));
    bool shaped = bigmodel::canonical(r.word());
    if (mpz_cmp(r.value(), a.value()) != 0) {
      explainValues("big_from_str of big_show gives %#Zx", r.value());
      ok = false;
    }
    static constexpr const char *forms[] = {"large", "small"};
    tally.classify(forms[a.word() & 1]);
    return ok && shaped;
  });

  run.box("box: every string of at most 3 characters over the literal alphabet", shortStrings, [](uint64_t input) {
    char text[3];
    size_t n = shortString(input, text);
    Z value;
    castValue(text, n, value);
    return reads(text, n, value);
  });

  run.property("every operation borrows its argument and returns one owned result",
               [](FuzzedDataProvider &p, prop::Tally &tally) {
                 uint64_t mask = prop::swarm(p, magnitudeFamilies);
                 uint64_t word = drawWord(p, prop::pick(p, prop::swarm(p, wordFamilies)));
                 Z v;
                 bigmodel::draw(p, prop::pick(p, prop::swarm(p, bigmodel::families)), v);
                 Operand constant(v);
                 Literal literal;
                 generate(p, mask, drawBase(p), literal);
                 uint64_t live = idris_rt_live_cells();
                 bool ok = true;
                 {
                   // Counted operands: the big negated twice, a new cell when it
                   // is large; the literal's string, new.
                   Result negated(idris_rt_big_neg(constant.word()));
                   Result big(idris_rt_big_neg(negated.word()));
                   Text s(idris_rt_str_from_utf8(literal.text, literal.length));
                   ok &= borrows("show_s", nothing(), [&] { return idris_rt_str_show_s(static_cast<int64_t>(word)); });
                   ok &= borrows("show_u", nothing(), [&] { return idris_rt_str_show_u(word); });
                   ok &= borrows("big_show", asPointer(big.word()), [&] { return idris_rt_big_show(big.word()); });
                   ok &= borrows("big_from_str", s.get(), [&] { return asPointer(idris_rt_big_from_str(s.get())); });
                   ok &= borrows("str_to_int", s.get(), [&] {
                     (void)idris_rt_str_to_int(s.get());
                     return nothing();
                   });
                   static constexpr const char *forms[] = {"large", "small"};
                   tally.classify(forms[big.word() & 1]);
                 }
                 if (idris_rt_live_cells() != live) {
                   prop::explain("live cells %llu before the operands were made, %llu after",
                                 static_cast<unsigned long long>(live),
                                 static_cast<unsigned long long>(idris_rt_live_cells()));
                   ok = false;
                 }
                 return ok;
               });

  return run.finish();
}
