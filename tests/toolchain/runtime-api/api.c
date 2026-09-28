/* rule: TC-RT-4, LOW-BIG-1, LOW-STR-2, SEM-STR-2, SEM-INT-3
 * The runtime's string and big operations against Chez: `api` prints one
 * line per operation, and chez.ss prints what Chez computes for the same
 * operations, which the run script compares. Then the casts from String,
 * whose grammar is ours (idris_rt.h), are checked against a table. */
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

static void text(const char *s) { idris_rt_put_str(idris_rt_str_from_utf8(s, strlen(s))); }
static void big(idris_rt_big b) { idris_rt_put_str(idris_rt_big_show(b)); }
static void line(void) { idris_rt_put_char('\n'); }
static void str(const idris_rt_str *s) {
  idris_rt_put_char('"');
  idris_rt_put_str(s);
  idris_rt_put_char('"');
}
static const idris_rt_str *make(const char *s) { return idris_rt_str_from_utf8(s, strlen(s)); }

static int failures = 0, checks = 0;

static void expectInt(const char *s, int64_t want) {
  int64_t got = idris_rt_str_to_int(make(s));
  idris_rt_big b = idris_rt_big_from_str(make(s));
  ++checks;
  if (got != want || idris_rt_big_to_int(b) != want) {
    fprintf(stderr, "FAIL to_int \"%s\": %lld\n", s, (long long)got);
    ++failures;
  }
}

static void expectBig(const char *s, const char *want) {
  const idris_rt_str *shown = idris_rt_big_show(idris_rt_big_from_str(make(s)));
  ++checks;
  if (shown->bytes != strlen(want) || memcmp(idris_rt_str_bytes(shown), want, shown->bytes) != 0) {
    fprintf(stderr, "FAIL big_from_str \"%s\"\n", s);
    ++failures;
  }
}

static void expectDouble(const char *s, double want) {
  double got = idris_rt_str_to_double(make(s));
  ++checks;
  if (memcmp(&got, &want, sizeof got) != 0 && !(got != got && want != want)) {
    fprintf(stderr, "FAIL to_double \"%s\"\n", s);
    ++failures;
  }
}

int main(void) {
  idris_rt_big values[bigCount];
  for (int i = 0; i < bigCount; ++i)
    values[i] = idris_rt_big_from_str(make(bigs[i]));
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
      idris_rt_put_int_s(idris_rt_big_compare(values[i], values[j]));
      line();
    }
    text("neg ");
    big(idris_rt_big_neg(values[i]));
    text(" to_int ");
    idris_rt_put_int_s(idris_rt_big_to_int(values[i]));
    text(" to_double ");
    idris_rt_put_double(idris_rt_big_to_double(values[i]));
    line();
  }
  for (int i = 0; i < doubleCount; ++i) {
    text("from_double ");
    big(idris_rt_big_from_double(doubles[i]));
    text(" show ");
    str(idris_rt_str_show_double(doubles[i]));
    line();
  }
  for (int i = 0; i < stringCount; ++i) {
    const idris_rt_str *s = make(strings[i]);
    int64_t n = idris_rt_str_length(s);
    text("length ");
    idris_rt_put_int_s(n);
    text(" chars");
    for (int64_t k = 0; k < n; ++k) {
      text(" ");
      idris_rt_put_int_s(idris_rt_str_index(s, k));
    }
    if (n > 0) {
      text(" head ");
      idris_rt_put_int_s(idris_rt_str_head(s));
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
      int32_t c = idris_rt_str_compare(s, t);
      text("compare ");
      idris_rt_put_int_s(c < 0 ? -1 : c > 0 ? 1 : 0);
      text(" append ");
      str(idris_rt_str_append(s, t));
      line();
    }
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
  return failures == 0 ? 0 : 1;
}
