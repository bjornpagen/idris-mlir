/* Constant folding, as Main.idr here (Perceus's cfold.kk), in C. The
   expression is never shared, so reassociation and folding update the
   cells in place and free the ones they drop: what full reuse achieves.
   Appending to a chain is a loop (what tail recursion modulo cons makes of
   it); folding and evaluating recurse as deep as the chain is long. */
#include <stdio.h>
#include <stdlib.h>

enum { VAR, VAL, ADD, MUL };

typedef struct E {
  int tag;
  long v;               /* VAR, VAL */
  struct E *a, *b;      /* ADD, MUL */
} E;

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static E *mk(int tag, long v, E *a, E *b) {
  E *e = malloc(sizeof *e);
  e->tag = tag; e->v = v; e->a = a; e->b = b;
  return e;
}

static E *mk_expr(long n, long v) {
  if (n == 0) return v == 0 ? mk(VAR, 1, NULL, NULL) : mk(VAL, v, NULL, NULL);
  E *a = mk_expr(n - 1, v + 1);
  E *b = mk_expr(n - 1, v - 1 > 0 ? v - 1 : 0);
  return mk(ADD, 0, a, b);
}

/* appendAdd e0 e3 (or appendMul, with tag MUL), where cell is a free cell
   that becomes the last node of the chain. */
static E *append(int tag, E *cell, E *e0, E *e3) {
  E **p = &e0;
  while ((*p)->tag == tag) p = &(*p)->b;
  cell->tag = tag; cell->a = *p; cell->b = e3;
  *p = cell;
  return e0;
}

static E *reassoc(E *e) {
  if (e->tag == ADD || e->tag == MUL) {
    E *a = reassoc(e->a);
    E *b = reassoc(e->b);
    return append(e->tag, e, a, b);
  }
  return e;
}

static E *cfold(E *e) {
  if (e->tag != ADD && e->tag != MUL) return e;
  int tag = e->tag;
  E *a = e->a = cfold(e->a);
  E *b = e->b = cfold(e->b);
  if (a->tag != VAL) return e;
  long x = a->v;
  if (b->tag == VAL) {        /* Val (a + b) */
    e->tag = VAL; e->v = tag == ADD ? x + b->v : x * b->v;
    free(a); free(b);
    return e;
  }
  if (b->tag == tag && b->b->tag == VAL) {   /* op f (Val b) */
    E *f = b->a, *vb = b->b;
    a->v = tag == ADD ? x + vb->v : x * vb->v;
    e->b = f;
    free(b); free(vb);
    return e;
  }
  if (b->tag == tag && b->a->tag == VAL) {   /* op (Val b) f */
    E *vb = b->a, *f = b->b;
    a->v = tag == ADD ? x + vb->v : x * vb->v;
    e->b = f;
    free(b); free(vb);
    return e;
  }
  return e;
}

static long eval(const E *e) {
  switch (e->tag) {
  case VAR: return 0;
  case VAL: return e->v;
  case ADD: return eval(e->a) + eval(e->b);
  default: return eval(e->a) * eval(e->b);
  }
}

static void drop(E *e) {
  while (e) {
    E *next = NULL;
    if (e->tag == ADD || e->tag == MUL) { drop(e->a); next = e->b; }
    free(e);
    e = next;
  }
}

int main(void) {
  long n = read_int();
  E *e = mk_expr(n, 1);
  long v1 = eval(e);
  e = cfold(reassoc(e));
  long v2 = eval(e);
  printf("%ld %ld\n", v1, v2);
  drop(e);
  return 0;
}
