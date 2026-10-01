/* spectral-norm on one core, as Main.idr here: ten rounds of the power
   method, each sum in index order. */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static double A(int i, int j) { return 1.0 / ((i + j) * (i + j + 1) / 2 + i + 1); }

static void mul_av(int n, const double *v, double *out) {
  for (int i = 0; i < n; i++) {
    double s = 0;
    for (int j = 0; j < n; j++) s += A(i, j) * v[j];
    out[i] = s;
  }
}

static void mul_atv(int n, const double *v, double *out) {
  for (int i = 0; i < n; i++) {
    double s = 0;
    for (int j = 0; j < n; j++) s += A(j, i) * v[j];
    out[i] = s;
  }
}

static void mul_atav(int n, const double *v, double *out, double *tmp) {
  mul_av(n, v, tmp);
  mul_atv(n, tmp, out);
}

int main(void) {
  int n = (int)read_int();
  double *u = malloc(n * sizeof *u), *v = malloc(n * sizeof *v), *tmp = malloc(n * sizeof *tmp);
  for (int i = 0; i < n; i++) u[i] = 1.0;
  for (int i = 0; i < 10; i++) { mul_atav(n, u, v, tmp); mul_atav(n, v, u, tmp); }
  double vbv = 0, vv = 0;
  for (int i = 0; i < n; i++) { vbv += u[i] * v[i]; vv += v[i] * v[i]; }
  printf("%0.9f\n", sqrt(vbv / vv));
  return 0;
}
