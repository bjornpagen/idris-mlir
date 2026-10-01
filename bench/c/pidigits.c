/* pidigits on one core, as Main.idr here: Gibbons's spigot on GMP
   integers, ten digits to a line. */
#include <gmp.h>
#include <stdio.h>

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

int main(void) {
  long total = read_int(), i = 0;
  unsigned long k = 0, k1 = 1;
  mpz_t n, a, d, t, u;
  mpz_init_set_ui(n, 1); mpz_init_set_ui(a, 0); mpz_init_set_ui(d, 1); mpz_init(t); mpz_init(u);
  char line[11];
  int col = 0;
  for (;;) {
    k++;
    mpz_mul_2exp(t, n, 1);
    mpz_mul_ui(n, n, k);
    mpz_add(a, a, t);
    k1 += 2;
    mpz_mul_ui(a, a, k1);
    mpz_mul_ui(d, d, k1);
    if (mpz_cmp(a, n) < 0) continue;
    mpz_mul_ui(t, n, 3);
    mpz_add(t, t, a);
    mpz_tdiv_qr(t, u, t, d);
    mpz_add(u, u, n);
    if (mpz_cmp(d, u) <= 0) continue;
    unsigned long digit = mpz_get_ui(t);
    line[col++] = (char)('0' + digit);
    i++;
    if (col == 10) { line[col] = 0; printf("%s\t:%ld\n", line, i); col = 0; }
    if (i >= total) {
      if (col != 0) { while (col < 10) line[col++] = ' '; line[col] = 0; printf("%s\t:%ld\n", line, i); }
      break;
    }
    mpz_submul_ui(a, d, digit);
    mpz_mul_ui(a, a, 10);
    mpz_mul_ui(n, n, 10);
  }
  return 0;
}
