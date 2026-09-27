#include <stdio.h>
static long readInt(void) { long n = 0; int c; while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0'); return n; }
int main(void) {
  long n = readInt(), best = 0, at = 1;
  for (long i = 1; i < n; i++) { long m = i, s = 0; while (m != 1) { m = m % 2 == 0 ? m / 2 : 3 * m + 1; s++; } if (s > best) { best = s; at = i; } }
  printf("%ld\n", at); return 0; }
