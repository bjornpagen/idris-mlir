#include <stdio.h>
static long readInt(void) { long n = 0; int c; while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0'); return n; }
static long tak(long x, long y, long z) { return y < x ? tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y)) : z; }
int main(void) { long n = readInt(), acc = 0; for (long k = 1000; k > 0; k--) acc += tak(n + k % 2, 2 * n / 3, n / 3); printf("%ld\n", acc); return 0; }
