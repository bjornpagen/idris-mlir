// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The parser benchmarks' programs in C: every line of stdin parsed as a
   JSON value, or, where it is none, as an arithmetic expression, by
   recursive descent over the line and a position, as Main.idr here does
   it by hand and the other parser benchmarks with combinators. Prints how
   many lines were JSON, their nodes and the sum of their numbers; how
   many were expressions and the sum of their values; and how many were
   neither. */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>

static long skip(const char *t, long n, long i) {
  while (i < n && isspace((unsigned char)t[i])) i++;
  return i;
}

static int lit(const char *t, long n, long i, const char *w) {
  long k = (long)strlen(w);
  return i + k <= n && memcmp(t + i, w, (size_t)k) == 0;
}

/* An optional minus and one digit at least, then spaces. */
static int number(const char *t, long n, long *i, long long *v) {
  long j = *i;
  int neg = 0;
  if (j < n && t[j] == '-') { neg = 1; j++; }
  if (!(j < n && isdigit((unsigned char)t[j]))) return 0;
  long long acc = 0;
  while (j < n && isdigit((unsigned char)t[j])) acc = acc * 10 + (t[j++] - '0');
  *v = neg ? -acc : acc;
  *i = skip(t, n, j);
  return 1;
}

static int str(const char *t, long n, long *i) {
  long j = *i;
  if (!(j < n && t[j] == '"')) return 0;
  j++;
  while (j < n && t[j] != '"') j++;
  if (j >= n) return 0;
  *i = skip(t, n, j + 1);
  return 1;
}

static int sym(const char *t, long n, long *i, char c) {
  if (*i < n && t[*i] == c) { *i = skip(t, n, *i + 1); return 1; }
  return 0;
}

/* A JSON value: its nodes added to *size and its numbers to *sum. */
static int value(const char *t, long n, long *i, long long *size, long long *sum) {
  long j = *i;
  if (j >= n) return 0;
  switch (t[j]) {
  case 'n':
    if (!lit(t, n, j, "null")) return 0;
    *i = skip(t, n, j + 4); *size += 1; return 1;
  case 't':
    if (!lit(t, n, j, "true")) return 0;
    *i = skip(t, n, j + 4); *size += 1; return 1;
  case 'f':
    if (!lit(t, n, j, "false")) return 0;
    *i = skip(t, n, j + 5); *size += 1; return 1;
  case '"':
    if (!str(t, n, &j)) return 0;
    *i = j; *size += 1; return 1;
  case '[':
    j = skip(t, n, j + 1);
    *size += 1;
    if (sym(t, n, &j, ']')) { *i = j; return 1; }
    for (;;) {
      if (!value(t, n, &j, size, sum)) return 0;
      if (sym(t, n, &j, ',')) continue;
      if (sym(t, n, &j, ']')) { *i = j; return 1; }
      return 0;
    }
  case '{':
    j = skip(t, n, j + 1);
    *size += 1;
    if (sym(t, n, &j, '}')) { *i = j; return 1; }
    for (;;) {
      if (!str(t, n, &j) || !sym(t, n, &j, ':') || !value(t, n, &j, size, sum)) return 0;
      if (sym(t, n, &j, ',')) continue;
      if (sym(t, n, &j, '}')) { *i = j; return 1; }
      return 0;
    }
  default: {
    long long v;
    if (!number(t, n, &j, &v)) return 0;
    *i = j; *size += 1; *sum += v; return 1;
  }
  }
}

static int expr(const char *t, long n, long *i, long long *v);

/* Division rounds toward negative infinity for a positive divisor and
   keeps the remainder non-negative, as Euclidean division does; the input
   the benchmarks read divides nothing. */
static long long divide(long long a, long long b) {
  long long q = a / b, r = a % b;
  if (r < 0) q += b > 0 ? -1 : 1;
  return q;
}

static int factor(const char *t, long n, long *i, long long *v) {
  if (number(t, n, i, v)) return 1;
  long j = *i;
  long long x;
  if (!sym(t, n, &j, '(') || !expr(t, n, &j, &x) || !sym(t, n, &j, ')')) return 0;
  *i = j; *v = x;
  return 1;
}

static int term(const char *t, long n, long *i, long long *v) {
  long long acc;
  if (!factor(t, n, i, &acc)) return 0;
  for (;;) {
    long j = *i;
    long long y;
    if (sym(t, n, &j, '*') && factor(t, n, &j, &y)) { acc = acc * y; *i = j; continue; }
    j = *i;
    if (sym(t, n, &j, '/') && factor(t, n, &j, &y)) { acc = divide(acc, y); *i = j; continue; }
    break;
  }
  *v = acc;
  return 1;
}

static int expr(const char *t, long n, long *i, long long *v) {
  long long acc;
  if (!term(t, n, i, &acc)) return 0;
  for (;;) {
    long j = *i;
    long long y;
    if (sym(t, n, &j, '+') && term(t, n, &j, &y)) { acc = acc + y; *i = j; continue; }
    j = *i;
    if (sym(t, n, &j, '-') && term(t, n, &j, &y)) { acc = acc - y; *i = j; continue; }
    break;
  }
  *v = acc;
  return 1;
}

int main(void) {
  long long jsons = 0, nodes = 0, numbers = 0, exprs = 0, total = 0, errors = 0;
  char *line = NULL;
  size_t cap = 0;
  ssize_t got;
  while ((got = getline(&line, &cap, stdin)) > 0) {
    long n = (long)got;
    if (line[n - 1] == '\n') n--;
    if (n == 0) break;
    long start = skip(line, n, 0), i = start;
    long long size = 0, sum = 0, v;
    if (value(line, n, &i, &size, &sum) && i >= n) {
      jsons++; nodes += size; numbers += sum;
      continue;
    }
    i = start;
    if (expr(line, n, &i, &v) && i >= n) {
      exprs++; total += v;
      continue;
    }
    errors++;
  }
  free(line);
  printf("json %lld size %lld sum %lld\n", jsons, nodes, numbers);
  printf("expr %lld sum %lld\n", exprs, total);
  printf("error %lld\n", errors);
  return 0;
}
