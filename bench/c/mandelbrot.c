#include <stdio.h>
static long readInt(void) { long n = 0; int c; while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0'); return n; }
static int escapes(double cr, double ci) {
  double zr = 0, zi = 0;
  for (int i = 0; i < 50; i++) { double zr2 = zr * zr, zi2 = zi * zi; if (zr2 + zi2 > 4.0) return 1; zi = 2.0 * zr * zi + ci; zr = zr2 - zi2 + cr; }
  return 0; }
int main(void) {
  long n = readInt(), acc = 0;
  for (long y = 0; y < n; y++) { double ci = 2.0 * (double)y / (double)n - 1.0;
    for (long x = 0; x < n; x++) { double cr = 2.0 * (double)x / (double)n - 1.5; if (!escapes(cr, ci)) acc++; } }
  printf("%ld\n", acc); return 0; }
