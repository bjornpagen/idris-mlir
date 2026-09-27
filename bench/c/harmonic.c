#include <stdio.h>
static long readInt(void) { long n = 0; int c; while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0'); return n; }
int main(void) {
  long n = readInt(); double h = 0.0, a = 0.0;
  for (long i = 1; i <= n; i++) { double x = 1.0 / (double)i; h += x; a = i % 2 == 0 ? a - x : a + x; }
  printf("%.17g\n%.17g\n", h, a); return 0;
}
