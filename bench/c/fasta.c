/* fasta on one core, as Main.idr here: the repeated ALU and two random
   sequences from cumulative tables, 60 characters to a line. */
#include <stdio.h>
#include <string.h>

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static const char alu[] =
    "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGG"
    "GAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGA"
    "CCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAAT"
    "ACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCA"
    "GCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGG"
    "AGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCC"
    "AGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";

typedef struct { char c; double p; } Sym;

static Sym iub[] = {{'a', 0.27}, {'c', 0.12}, {'g', 0.12}, {'t', 0.27}, {'B', 0.02}, {'D', 0.02},
                    {'H', 0.02}, {'K', 0.02}, {'M', 0.02}, {'N', 0.02}, {'R', 0.02}, {'S', 0.02},
                    {'V', 0.02}, {'W', 0.02}, {'Y', 0.02}};
static Sym homo[] = {{'a', 0.3029549426680}, {'c', 0.1979883004921},
                     {'g', 0.1975473066391}, {'t', 0.3015094502008}};

static void cumulative(Sym *t, int n) {
  double acc = 0;
  for (int i = 0; i < n; i++) { acc += t[i].p; t[i].p = acc; }
}

#define IM 139968
#define IA 3877
#define IC 29573
static int seed = 42;
static double random_(void) {
  seed = (seed * IA + IC) % IM;
  return 1.0 * seed / IM;
}

static void repeat_fasta(long n) {
  int len = (int)strlen(alu), k = 0;
  char line[61];
  while (n > 0) {
    int m = n < 60 ? (int)n : 60;
    for (int i = 0; i < m; i++) line[i] = alu[(k + i) % len];
    line[m] = 0;
    puts(line);
    k = (k + m) % len;
    n -= m;
  }
}

static void random_fasta(Sym *t, int count, long n) {
  char line[61];
  while (n > 0) {
    int m = n < 60 ? (int)n : 60;
    for (int i = 0; i < m; i++) {
      double r = random_();
      int j = 0;
      while (j < count - 1 && r >= t[j].p) j++;
      line[i] = t[j].c;
    }
    line[m] = 0;
    puts(line);
    n -= m;
  }
}

int main(void) {
  long n = read_int();
  cumulative(iub, sizeof iub / sizeof *iub);
  cumulative(homo, sizeof homo / sizeof *homo);
  puts(">ONE Homo sapiens alu");
  repeat_fasta(n * 2);
  puts(">TWO IUB ambiguity codes");
  random_fasta(iub, sizeof iub / sizeof *iub, n * 3);
  puts(">THREE Homo sapiens frequency");
  random_fasta(homo, sizeof homo / sizeof *homo, n * 5);
  return 0;
}
