// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* The parser benchmarks' input, as Main.idr here: n lines from one
   pseudo-random sequence, JSON objects on the even lines, arithmetic
   expressions on the odd ones, every sixteenth an unclosed array. Every
   draw is its own statement, so the draws happen in the order Main.idr
   threads its seed. */
#include <stdio.h>

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static long long seed = 42;

static long long roll(long long k) {
  seed = (seed * 1103515245LL + 12345LL) % 2147483648LL;
  return (seed / 65536) % k;
}

static void value(int d);

static void json_number(void) {
  long long v = roll(1000);
  long long neg = roll(4);
  printf("%s%lld", neg == 0 && v > 0 ? "-" : "", v);
}

static void members(int d, long long c) {
  putchar('{');
  for (long long i = 0; i < c; i++) {
    if (i > 0) fputs(", ", stdout);
    printf("\"m%lld\": ", i);
    value(d);
  }
  putchar('}');
}

static void value(int d) {
  long long r = roll(d < 3 ? 8 : 6);
  switch (r) {
  case 0: fputs("null", stdout); break;
  case 1: fputs("true", stdout); break;
  case 2: fputs("false", stdout); break;
  case 5: printf("\"k%lld\"", roll(100)); break;
  case 6: {
    long long c = roll(4);
    putchar('[');
    for (long long i = 0; i < c; i++) {
      if (i > 0) fputs(", ", stdout);
      value(d + 1);
    }
    putchar(']');
    break;
  }
  case 7: {
    long long c = roll(4);
    members(d + 1, c);
    break;
  }
  default: json_number(); break;
  }
}

static void terms(int d, long long t);

static void factor(int d) {
  if (d < 1 && roll(4) == 0) {
    long long t = roll(3);
    putchar('(');
    terms(d + 1, 1 + t);
    putchar(')');
  } else {
    printf("%lld", roll(100));
  }
}

static void term(int d) {
  long long f = 1 + roll(2);
  for (long long i = 0; i < f; i++) {
    if (i > 0) fputs(" * ", stdout);
    factor(d);
  }
}

static void terms(int d, long long t) {
  for (long long i = 0; i < t; i++) {
    if (i > 0) {
      long long op = roll(2);
      fputs(op == 0 ? " + " : " - ", stdout);
    }
    term(d);
  }
}

int main(void) {
  long n = read_int();
  for (long k = 0; k < n; k++) {
    if (k % 16 == 15) {
      long long a = roll(100);
      long long b = roll(100);
      printf("[%lld, %lld", a, b);
    } else if (k % 2 == 0) {
      long long c = roll(4);
      members(1, 3 + c);
    } else {
      long long t = roll(3);
      terms(0, 2 + t);
    }
    putchar('\n');
  }
  return 0;
}
