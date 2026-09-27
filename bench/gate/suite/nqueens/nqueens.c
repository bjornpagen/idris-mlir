/* All solutions of the n-queens problem, as Main.idr here (Perceus's
   nqueens.kk), in C. Solutions share their tails, so cons cells carry
   counts. */
#include <stdio.h>
#include <stdlib.h>

typedef struct Cell {  /* a cons cell of a solution: a queen and the rest */
  long rc;
  long q;
  struct Cell *next;
} Cell;

typedef struct Sols {  /* a cons cell of the list of solutions */
  Cell *head;
  struct Sols *tail;
} Sols;

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static void dec(Cell *c) {
  while (c && --c->rc == 0) {
    Cell *next = c->next;
    free(c);
    c = next;
  }
}

static int safe(long queen, long diag, const Cell *xs) {
  for (; xs; xs = xs->next, diag++)
    if (queen == xs->q || queen == xs->q + diag || queen == xs->q - diag) return 0;
  return 1;
}

/* appendSafe queen xs xss: xs is borrowed, xss is consumed. */
static Sols *append_safe(long queen, Cell *xs, Sols *xss) {
  for (; queen > 0; queen--) {
    if (safe(queen, 1, xs)) {
      Cell *c = malloc(sizeof *c);
      c->rc = 1; c->q = queen; c->next = xs;
      if (xs) xs->rc++;
      Sols *s = malloc(sizeof *s);
      s->head = c; s->tail = xss;
      xss = s;
    }
  }
  return xss;
}

/* extend queen acc xss: consumes acc and xss. */
static Sols *extend(long queen, Sols *acc, Sols *xss) {
  while (xss) {
    Sols *rest = xss->tail;
    acc = append_safe(queen, xss->head, acc);
    dec(xss->head);
    free(xss);
    xss = rest;
  }
  return acc;
}

static Sols *find_solutions(long n, long queen) {
  if (queen == 0) {
    Sols *s = malloc(sizeof *s);
    s->head = NULL; s->tail = NULL;
    return s;
  }
  return extend(n, NULL, find_solutions(n, queen - 1));
}

int main(void) {
  long n = read_int();
  Sols *s = find_solutions(n, n);
  long len = 0;
  while (s) {
    Sols *rest = s->tail;
    len++;
    dec(s->head);
    free(s);
    s = rest;
  }
  printf("%ld\n", len);
  return 0;
}
