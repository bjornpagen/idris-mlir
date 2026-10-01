/* Binary trees on one core, as Main.idr here (Lean's binarytrees.st.lean),
   in C with malloc and free. */
#include <stdio.h>
#include <stdlib.h>

typedef struct Node { struct Node *l, *r; } Node;

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

/* The unused seed mirrors make' in the other versions. */
static Node *make_(long n, long d) {
  Node *t = malloc(sizeof *t);
  if (d == 0) { t->l = t->r = NULL; }
  else { t->l = make_(n, d - 1); t->r = make_(n + 1, d - 1); }
  return t;
}

static Node *make(long d) { return make_(d, d); }

static long check(const Node *t) { return t ? 1 + check(t->l) + check(t->r) : 0; }

static void drop(Node *t) {
  if (t) { drop(t->l); drop(t->r); free(t); }
}

static long sum_t(long d, long i, long t) {
  for (; i != 0; i--) {
    Node *x = make_(i, d);
    t += check(x);
    drop(x);
  }
  return t;
}

int main(void) {
  long n = read_int();
  long min_n = 4;
  long max_n = min_n + 2 > n ? min_n + 2 : n;
  long stretch_n = max_n + 1;
  Node *s = make(stretch_n);
  printf("stretch tree of depth %ld\t check: %ld\n", stretch_n, check(s));
  drop(s);
  Node *long_lived = make(max_n);
  for (long d = min_n; d <= max_n; d += 2) {
    long k = 1L << (max_n - d + min_n);
    printf("%ld\t trees of depth %ld\t check: %ld\n", k, d, sum_t(d, k, 0));
  }
  printf("long lived tree of depth %ld\t check: %ld\n", max_n, check(long_lived));
  drop(long_lived);
  return 0;
}
