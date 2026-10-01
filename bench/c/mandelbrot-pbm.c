/* mandelbrot on one core, as Main.idr here: a portable bitmap, eight
   pixels to a byte, fifty iterations, scalar. */
#include <stdio.h>

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static int in_set(double cr, double ci) {
  double zr = 0, zi = 0;
  for (int i = 0; i < 50; i++) {
    double zr2 = zr * zr, zi2 = zi * zi;
    if (zr2 + zi2 > 4.0) return 0;
    zi = 2.0 * zr * zi + ci;
    zr = zr2 - zi2 + cr;
  }
  return 1;
}

int main(void) {
  long n = read_int();
  printf("P4\n%ld %ld\n", n, n);
  for (long y = 0; y < n; y++) {
    double ci = 2.0 * (double)y / (double)n - 1.0;
    for (long x = 0; x < n; x += 8) {
      int byte = 0;
      for (int k = 0; k < 8; k++) {
        long px = x + k;
        int bit = px < n && in_set(2.0 * (double)px / (double)n - 1.5, ci);
        byte = byte * 2 + bit;
      }
      putchar(byte);
    }
  }
  return 0;
}
