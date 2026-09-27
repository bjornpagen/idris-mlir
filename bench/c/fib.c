#include <stdio.h>
static long readInt(void) { long n = 0; int c; while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0'); return n; }
static long fib(long n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
int main(void) { printf("%ld\n", fib(readInt())); return 0; }
