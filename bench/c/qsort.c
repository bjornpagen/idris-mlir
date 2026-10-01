/* Quicksort of arrays of 32-bit words, as Main.idr here (Lean's
   qsort.lean), in C. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static uint32_t bad_rand(uint32_t seed) { return seed * 1664525u + 1013904223u; }

static void swap(uint32_t *a, long i, long j) { uint32_t x = a[i]; a[i] = a[j]; a[j] = x; }

static long partition(uint32_t *a, long lo, long hi) {
  long mid = (lo + hi) / 2;
  if (a[mid] < a[lo]) swap(a, lo, mid);
  if (a[hi] < a[lo]) swap(a, lo, hi);
  if (a[mid] < a[hi]) swap(a, mid, hi);
  uint32_t pivot = a[hi];
  long i = lo;
  for (long j = lo; j < hi; j++)
    if (a[j] < pivot) { swap(a, i, j); i++; }
  swap(a, i, hi);
  return i;
}

static void qsort_aux(uint32_t *a, long low, long high) {
  while (low < high) {
    long mid = partition(a, low, high);
    qsort_aux(a, low, mid);
    low = mid + 1;
  }
}

/* Sorts arrays of every size i < n; returns the sum of their middle
   elements, or -1 if one is not sorted. */
static long sizes(long n) {
  long acc = 0;
  for (long i = 0; i < n; i++) {
    uint32_t *a = malloc((size_t)(i > 0 ? i : 1) * sizeof *a);
    uint32_t s = (uint32_t)i;
    for (long j = 0; j < i; j++) { a[j] = s; s = bad_rand(s); }
    qsort_aux(a, 0, i - 1);
    for (long j = 0; j + 1 < i; j++)
      if (a[j] > a[j + 1]) { free(a); return -1; }
    if (i > 0) acc += a[i / 2];
    free(a);
  }
  return acc;
}

int main(void) {
  long n = read_int();
  long total = 0;
  for (long k = 0; k < n; k++) {
    long s = sizes(n);
    if (s < 0) { puts("array is not sorted"); return 0; }
    total += s;
  }
  printf("%ld\n", total);
  return 0;
}
