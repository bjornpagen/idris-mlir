/* The runtime's string and big operations against Chez: `api` prints one
 * line per operation, and chez.ss prints what Chez computes for the same
 * operations, which the run script compares. Then the casts from String,
 * whose grammar is ours (idris_rt.h), and the decoding of bytes from
 * outside the program, are checked against tables.
 *
 * Every operation borrows its arguments and returns an owned result, so
 * each result is released once, when it has been printed, and each argument
 * by whoever made it. Then no cell is live at the end, and no string or big
 * is freed while something still uses it. */
#include <stdio.h>
#include <string.h>

#include "idris_rt.h"

static const char *const bigs[] = {
    "0", "1", "-1", "7", "-7", "2", "-2", "4611686018427387903", "4611686018427387904",
    "-4611686018427387904", "-4611686018427387905", "9223372036854775807",
    "9223372036854775808", "-9223372036854775808", "18446744073709551616",
    "123456789012345678901234567890", "-98765432109876543210987654321",
    "340282366920938463463374607431768211457"};
enum { bigCount = sizeof bigs / sizeof bigs[0] };

static const char *const strings[] = {"", "a", "hello", "héllo wörld", "日本語", "\xF0\x9F\x98\x80x", "ab"};
enum { stringCount = sizeof strings / sizeof strings[0] };

static const double doubles[] = {0.0, -0.0, 0.5, -0.5, 123.9, -123.9, 4.6e18, -1.5e19, 1e300, 2.5e-310};
enum { doubleCount = sizeof doubles / sizeof doubles[0] };

static void release(const idris_rt_str *s) { idris_rt_dec((void *)s); }

/* The count of an object, and 0 for a small big. */
static uint32_t countOf(const void *o) {
  return ((uintptr_t)o & 1) != 0 ? 0 : ((const idris_rt_header *)o)->count;
}

static int borrowFailures = 0;

/* Releases an argument its maker owns. The operations only borrowed it, so
 * with every result they returned released, its count is what it was when it
 * was made. */
static void releaseArgument(const void *o, uint32_t made, const char *what) {
  if (countOf(o) != made) {
    fprintf(stderr, "FAIL an operation kept or dropped a reference to %s\n", what);
    ++borrowFailures;
  }
  idris_rt_dec((void *)o);
}
static const idris_rt_str *make(const char *s) { return idris_rt_str_from_utf8(s, strlen(s)); }
static void text(const char *s) {
  const idris_rt_str *t = make(s);
  idris_rt_io_put_str(t);
  release(t);
}
/* Prints b, an operation's result, and releases it. */
static void big(idris_rt_big b) {
  const idris_rt_str *shown = idris_rt_big_show(b);
  idris_rt_io_put_str(shown);
  release(shown);
  idris_rt_big_release(b);
}
static void line(void) { idris_rt_io_put_char('\n'); }
/* Prints s, an operation's result, and releases it. */
static void str(const idris_rt_str *s) {
  idris_rt_io_put_char('"');
  idris_rt_io_put_str(s);
  idris_rt_io_put_char('"');
  release(s);
}

static int failures = 0, checks = 0;

static void expectInt(const char *s, int64_t want) {
  const idris_rt_str *m = make(s);
  uint32_t made = countOf(m);
  int64_t got = idris_rt_str_to_int(m);
  idris_rt_big b = idris_rt_big_from_str(m);
  ++checks;
  if (got != want || idris_rt_big_to_int(b) != want) {
    fprintf(stderr, "FAIL to_int \"%s\": %lld\n", s, (long long)got);
    ++failures;
  }
  idris_rt_big_release(b);
  releaseArgument(m, made, s);
}

static void expectBig(const char *s, const char *want) {
  const idris_rt_str *m = make(s);
  uint32_t made = countOf(m);
  idris_rt_big b = idris_rt_big_from_str(m);
  uint32_t bigMade = countOf((void *)(uintptr_t)b);
  const idris_rt_str *shown = idris_rt_big_show(b);
  ++checks;
  if (shown->bytes != strlen(want) || memcmp(idris_rt_str_bytes(shown), want, shown->bytes) != 0) {
    fprintf(stderr, "FAIL big_from_str \"%s\"\n", s);
    ++failures;
  }
  release(shown);
  releaseArgument((void *)(uintptr_t)b, bigMade, s);
  releaseArgument(m, made, s);
}

static void expectDouble(const char *s, double want) {
  const idris_rt_str *m = make(s);
  uint32_t made = countOf(m);
  double got = idris_rt_str_to_double(m);
  releaseArgument(m, made, s);
  ++checks;
  if (memcmp(&got, &want, sizeof got) != 0 && !(got != got && want != want)) {
    fprintf(stderr, "FAIL to_double \"%s\"\n", s);
    ++failures;
  }
}

/* Every double's text reads back as the double, as IEEE 754 requires of
 * the two conversions, a NaN's as a NaN: the special values, the edges of
 * the subnormals and of the range, and pseudo-random bit patterns, a third
 * of them subnormal. */
static void roundTrip(void) {
  static const double edges[] = {0.0, -0.0, 1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0, 4.9e-324,
                                 -2.225073858507201e-308, 2.2250738585072014e-308,
                                 1.7976931348623157e308, 1e21, 1e-7, 0.1, 12.8868560791015625};
  enum { edgeCount = sizeof edges / sizeof edges[0], patterns = 30000 };
  int trips = 0, failed = 0;
  uint64_t state = 7;
  for (int i = 0; i < edgeCount + patterns; ++i) {
    double x;
    if (i < edgeCount) {
      x = edges[i];
    } else {
      state = state * 6364136223846793005u + 1442695040888963407u;
      uint64_t bits = state ^ (state >> 29);
      if (i % 3 == 0)
        bits &= 0x800FFFFFFFFFFFFFu;
      memcpy(&x, &bits, sizeof x);
    }
    const idris_rt_str *text = idris_rt_str_show_f64(x);
    uint32_t made = countOf(text);
    double back = idris_rt_str_to_double(text);
    ++trips;
    if (memcmp(&back, &x, sizeof x) != 0 && !(back != back && x != x)) {
      if (failed < 5)
        fprintf(stderr, "FAIL \"%.*s\" does not read back\n", (int)text->bytes, idris_rt_str_bytes(text));
      ++failed;
    }
    releaseArgument(text, made, "a double's text");
  }
  fprintf(stderr, "doubles read back from their text: %d of %d\n", trips - failed, trips);
  failures += failed;
}

static int decodeFailures = 0, decodeChecks = 0;

/* The n bytes at p become the string of the well-formed UTF-8 `want`:
 * the same bytes, scalar count and ASCII flag. */
static void expectDecoded(const char *p, size_t n, const char *want) {
  const idris_rt_str *got = idris_rt_str_from_bytes(p, n);
  const idris_rt_str *expected = make(want);
  ++decodeChecks;
  if (got->bytes != expected->bytes || got->scalars != expected->scalars ||
      memcmp(idris_rt_str_bytes(got), idris_rt_str_bytes(expected), got->bytes) != 0 ||
      idris_rt_str_is_ascii(got) != idris_rt_str_is_ascii(expected)) {
    fprintf(stderr, "FAIL from_bytes of %zu bytes, expected \"%s\"\n", n, want);
    ++decodeFailures;
  }
  release(got);
  release(expected);
}

/* Bytes from outside the program as a string: each maximal subpart of an
 * ill-formed sequence, the longest prefix of a well-formed one or else one
 * byte, is one U+FFFD (the Unicode Standard, chapter 3, whose table of
 * U+FFFD in UTF-8 conversion is the first case). */
static void decoding(void) {
#define FFFD "\xEF\xBF\xBD"
  static const char table[] = "\x61\xF1\x80\x80\xE1\x80\xC2\x62\x80\x63\x80\xBF\x64";
  expectDecoded(table, sizeof table - 1, "a" FFFD FFFD FFFD "b" FFFD "c" FFFD FFFD "d");
  expectDecoded("\x61\xE2\x82\x62", 4, "a" FFFD "b");
  expectDecoded("\xF0\x9F\x98\x63", 4, FFFD "c");
  expectDecoded("\xC0\x80\x64", 3, FFFD FFFD "d");
  expectDecoded("\xED\xA0\x80\x65", 4, FFFD FFFD FFFD "e");
  expectDecoded("\xE9\x66", 2, FFFD "f");
  expectDecoded("\xE9", 1, FFFD);
  expectDecoded("\xE0\x80\x80", 3, FFFD FFFD FFFD);
  expectDecoded("\xF0\x80\x80\x80", 4, FFFD FFFD FFFD FFFD);
  expectDecoded("\xF4\x90\x80\x80", 4, FFFD FFFD FFFD FFFD);
  expectDecoded("\xF4\x8F\xBF", 3, FFFD);
  expectDecoded("\xFF\xFE\x80", 3, FFFD FFFD FFFD);
  expectDecoded("\xE0\xA0\x80\xEF\xBF\xBF\xF4\x8F\xBF\xBF", 10, "\xE0\xA0\x80\xEF\xBF\xBF\xF4\x8F\xBF\xBF");
  expectDecoded("h\xC3\xA9llo \xE6\x97\xA5\xF0\x9F\x98\x80", 14, "h\xC3\xA9llo \xE6\x97\xA5\xF0\x9F\x98\x80");
  expectDecoded("", 0, "");
  /* Ill-formed bytes between runs longer than simdutf's blocks: a lead
   * byte with no continuation and a lone continuation byte, each one
   * U+FFFD of three bytes. */
  char runs[200];
  memset(runs, 'x', sizeof runs);
  runs[70] = '\xC3';
  runs[150] = '\xA9';
  char want[sizeof runs + 2 + 2 + 1];
  memset(want, 'x', sizeof want);
  memcpy(want + 70, FFFD, 3);
  memcpy(want + 152, FFFD, 3);
  want[sizeof want - 1] = '\0';
  expectDecoded(runs, sizeof runs, want);
#undef FFFD
  fprintf(stderr, "bytes as a string: %d of %d as idris_rt.h defines them\n",
          decodeChecks - decodeFailures, decodeChecks);
}

int main(void) {
  idris_rt_big values[bigCount];
  uint32_t made[bigCount];
  for (int i = 0; i < bigCount; ++i) {
    const idris_rt_str *digits = make(bigs[i]);
    uint32_t digitsMade = countOf(digits);
    values[i] = idris_rt_big_from_str(digits);
    made[i] = countOf((void *)(uintptr_t)values[i]);
    releaseArgument(digits, digitsMade, bigs[i]);
  }
  static const char *const names[] = {"add", "sub", "mul", "div", "mod", "and", "or", "xor"};
  idris_rt_big (*const ops[])(idris_rt_big, idris_rt_big) = {
      idris_rt_big_add, idris_rt_big_sub, idris_rt_big_mul, idris_rt_big_div,
      idris_rt_big_mod, idris_rt_big_and, idris_rt_big_or,  idris_rt_big_xor};
  for (int i = 0; i < bigCount; ++i) {
    for (int j = 0; j < bigCount; ++j) {
      for (int k = 0; k < 8; ++k) {
        if ((k == 3 || k == 4) && j == 0)
          continue;
        text(names[k]);
        text(" ");
        big(ops[k](values[i], values[j]));
        line();
      }
      text("compare ");
      idris_rt_io_put_int_s(idris_rt_big_cmp(values[i], values[j]));
      line();
    }
    text("neg ");
    big(idris_rt_big_neg(values[i]));
    text(" to_int ");
    idris_rt_io_put_int_s(idris_rt_big_to_int(values[i]));
    text(" to_double ");
    idris_rt_io_put_double(idris_rt_big_to_double(values[i]));
    line();
  }
  for (int i = 0; i < doubleCount; ++i) {
    text("from_double ");
    big(idris_rt_big_from_double(doubles[i]));
    text(" show ");
    str(idris_rt_str_show_f64(doubles[i]));
    line();
  }
  for (int i = 0; i < stringCount; ++i) {
    const idris_rt_str *s = make(strings[i]);
    uint32_t sMade = countOf(s);
    int64_t n = idris_rt_str_length(s);
    text("length ");
    idris_rt_io_put_int_s(n);
    text(" chars");
    for (int64_t k = 0; k < n; ++k) {
      text(" ");
      idris_rt_io_put_int_s(idris_rt_str_index(s, k));
    }
    if (n > 0) {
      text(" head ");
      idris_rt_io_put_int_s(idris_rt_str_head(s));
      text(" tail ");
      str(idris_rt_str_tail(s));
    }
    text(" reverse ");
    str(idris_rt_str_reverse(s));
    text(" cons ");
    str(idris_rt_str_cons(0xE9, s));
    line();
    for (int64_t start = -2; start <= 7; start += 3)
      for (int64_t len = -1; len <= 9; len += 5) {
        text("substr ");
        str(idris_rt_str_substr(s, start, len));
        line();
      }
    str(idris_rt_str_substr(s, 1, INT64_MAX));
    line();
    for (int j = 0; j < stringCount; ++j) {
      const idris_rt_str *t = make(strings[j]);
      uint32_t tMade = countOf(t);
      int32_t c = idris_rt_str_cmp(s, t);
      text("compare ");
      idris_rt_io_put_int_s(c < 0 ? -1 : c > 0 ? 1 : 0);
      text(" append ");
      str(idris_rt_str_append(s, t));
      line();
      releaseArgument(t, tMade, strings[j]);
    }
    releaseArgument(s, sMade, strings[i]);
  }
  static const int64_t ints[] = {0, 5, -5, INT64_MAX, INT64_MIN, 255};
  for (int i = 0; i < 6; ++i) {
    text("show ");
    str(idris_rt_str_show_s(ints[i]));
    text(" ");
    str(idris_rt_str_show_u((uint64_t)ints[i]));
    text(" ");
    str(idris_rt_str_from_char((int32_t)(ints[i] & 0xFFFF) + 0x41));
    line();
  }
  idris_rt_flush();
  for (int i = 0; i < bigCount; ++i)
    releaseArgument((void *)(uintptr_t)values[i], made[i], bigs[i]);

  expectInt("123", 123);
  expectInt("-45", -45);
  expectInt("+7", 7);
  expectInt("007", 7);
  expectInt("12.7", 12);
  expectInt("-12.7", -12);
  expectInt("1e3", 1000);
  expectInt(".5", 0);
  expectInt("5.", 5);
  expectInt(" 1", 0);
  expectInt("1 ", 0);
  expectInt("abc", 0);
  expectInt("", 0);
  expectInt("-", 0);
  expectInt("+", 0);
  expectInt("0x10", 0);
  expectInt("1_000", 0);
  expectInt("inf", 0);
  expectInt("nan", 0);
  expectInt("1e400", 0);
  expectInt("9223372036854775807", INT64_MAX);
  expectInt("9223372036854775808", INT64_MIN);
  expectInt("18446744073709551617", 1);
  expectBig("123456789012345678901234567890", "123456789012345678901234567890");
  expectBig("+123456789012345678901234567890", "123456789012345678901234567890");
  expectBig("-000123456789012345678901234567890", "-123456789012345678901234567890");
  expectBig("1e30", "1000000000000000019884624838656");
  expectBig("-2.5", "-2");
  expectBig("x", "0");
  expectDouble("1.5", 1.5);
  expectDouble("+1.5", 1.5);
  expectDouble("-1e-400", -0.0);
  expectDouble("1e400", 1.0 / 0.0);
  expectDouble("inf", 1.0 / 0.0);
  expectDouble("-Infinity", -1.0 / 0.0);
  expectDouble("nan", 0.0 / 0.0);
  expectDouble(".5", 0.5);
  expectDouble("5.", 5.0);
  expectDouble("1d3", 0.0);
  expectDouble("1/2", 0.0);
  expectDouble(" 1", 0.0);
  expectDouble("0x10", 0.0);
  expectDouble("", 0.0);
  fprintf(stderr, "casts from String: %d of %d as idris_rt.h defines them\n", checks - failures, checks);
  roundTrip();
  decoding();
  uint64_t live = idris_rt_live_cells();
  fprintf(stderr, "live cells once every result is released: %llu\n", (unsigned long long)live);
  return failures == 0 && decodeFailures == 0 && borrowFailures == 0 && live == 0 ? 0 : 1;
}
