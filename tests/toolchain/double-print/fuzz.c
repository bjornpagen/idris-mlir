/* rule: SEM-DBL-5, LOW-DBL-2
 * The runtime's Double printer against Chez's number->string. `fuzz N BITS`
 * writes N bit patterns to the file BITS, one per line in hex, and prints
 * each double with idris_rt_put_double, one per line; chez.ss prints the
 * same doubles from BITS. The patterns: any bits, exponents near 1023,
 * subnormals, and doubles whose decimal expansion ends in a 5, where the
 * shortest digits may be a tie (Ryu rounds a tie to even, Chez up). */
#include <inttypes.h>
#include <stdio.h>
#include <stdlib.h>

#include "idris_rt.h"

static uint64_t state = 42;

static uint64_t next(void) {
  state = state * 6364136223846793005u + 1442695040888963407u;
  return state ^ (state >> 29);
}

static uint64_t bitsOf(double x) {
  union { double d; uint64_t u; } v = {x};
  return v.u;
}

/* m * 2^e for an odd m of at most 53 bits, exactly. */
static uint64_t scaled(uint64_t m, int e) {
  int top = 63 - __builtin_clzll(m);
  int exponent = top + e + 1023;
  if (exponent <= 0 || exponent >= 2047 || top > 52)
    return 0;
  return (uint64_t)exponent << 52 | ((m << (52 - top)) & ((UINT64_C(1) << 52) - 1));
}

static uint64_t pattern(uint64_t i) {
  uint64_t r = next();
  uint64_t sign = (r & 1) << 63;
  switch (i % 6) {
  case 0:
    return r;
  case 1:
    return sign | (973 + (r >> 1) % 100) << 52 | (next() & ((UINT64_C(1) << 52) - 1));
  case 2:
    return sign | ((next() & ((UINT64_C(1) << 52) - 1)) >> (r >> 1) % 52);
  case 3: {
    /* An odd m times 2^-j: its decimal expansion ends in a 5. */
    int bits = 1 + (int)((r >> 1) % 53);
    uint64_t m = (next() >> (64 - bits)) | 1;
    return sign | scaled(m, -1 - (int)((r >> 8) % 1074));
  }
  case 4: {
    /* 2^50 <= t < 2^51 plus 0.25: a tie at 17 digits. */
    uint64_t t = (UINT64_C(1) << 50) + (next() & ((UINT64_C(1) << 50) - 1));
    return sign | bitsOf((double)t + 0.25);
  }
  default: {
    /* (10D + 5) * 10^p = (10D + 5) * 5^p * 2^p, when that is a double. */
    int p = (int)((r >> 1) % 23);
    uint64_t m = 10 * (next() % 100000000) + 5;
    for (int k = 0; k < p && m < (UINT64_C(1) << 53); ++k)
      m *= 5;
    return m < (UINT64_C(1) << 53) ? sign | scaled(m, p) : r;
  }
  }
}

int main(int argc, char **argv) {
  if (argc != 3)
    return 2;
  uint64_t n = strtoull(argv[1], NULL, 10);
  FILE *bits = fopen(argv[2], "w");
  if (bits == NULL)
    return 2;
  for (uint64_t i = 0; i < n; ++i) {
    uint64_t b = pattern(i);
    double x;
    union { uint64_t u; double d; } v = {b};
    x = v.d;
    fprintf(bits, "%016" PRIx64 "\n", b);
    idris_rt_put_double(x);
    idris_rt_put_char('\n');
  }
  idris_rt_flush();
  return fclose(bits) == 0 ? 0 : 1;
}
