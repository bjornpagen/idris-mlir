/* Symbolic differentiation, as Main.idr here (Perceus's deriv.kk), in C.
   Subterms are shared, so cells carry counts. Functions borrow their
   arguments and return a result the caller owns; there is no reuse. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { VAL, VAR, ADD, MUL, POW, LN };

typedef struct E {
  long rc;
  int tag;
  long v;               /* VAL */
  const char *name;     /* VAR */
  struct E *a, *b;      /* ADD, MUL, POW (a, b); LN (a) */
} E;

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static E *inc(E *e) { e->rc++; return e; }

static void dec(E *e) {
  while (e && --e->rc == 0) {
    E *next = NULL;
    if (e->tag >= ADD) {
      if (e->tag != LN) dec(e->a);
      next = e->tag == LN ? e->a : e->b;
    }
    free(e);
    e = next;
  }
}

static E *mk(int tag, E *a, E *b) {
  E *e = malloc(sizeof *e);
  e->rc = 1; e->tag = tag; e->v = 0; e->name = NULL; e->a = a; e->b = b;
  return e;
}

static E *val(long v) { E *e = mk(VAL, NULL, NULL); e->v = v; return e; }

static E *var(const char *name) { E *e = mk(VAR, NULL, NULL); e->name = name; return e; }

static long pown(long a, long n) {
  if (n == 0) return 1;
  if (n == 1) return a;
  long b = pown(a, n / 2);
  return b * b * (n % 2 == 0 ? 1 : a);
}

static int is_val(const E *e, long v) { return e->tag == VAL && e->v == v; }

/* Calls f(x, y) and drops the arguments that are temporaries: tt both,
   tb the first, bt the second. */
static E *tt(E *(*f)(E *, E *), E *x, E *y) { E *r = f(x, y); dec(x); dec(y); return r; }
static E *tb(E *(*f)(E *, E *), E *x, E *y) { E *r = f(x, y); dec(x); return r; }
static E *bt(E *(*f)(E *, E *), E *x, E *y) { E *r = f(x, y); dec(y); return r; }

static E *add(E *n, E *m) {
  if (n->tag == VAL && m->tag == VAL) return val(n->v + m->v);
  if (is_val(n, 0)) return inc(m);
  if (is_val(m, 0)) return inc(n);
  if (m->tag == VAL) return tb(add, val(m->v), n);
  if (n->tag == VAL && m->tag == ADD && m->a->tag == VAL)
    return tb(add, val(n->v + m->a->v), m->b);
  if (m->tag == ADD && m->a->tag == VAL)
    return tt(add, val(m->a->v), add(n, m->b));
  if (n->tag == ADD) { E *t = add(n->b, m); E *r = add(n->a, t); dec(t); return r; }
  return mk(ADD, inc(n), inc(m));
}

static E *mul(E *n, E *m) {
  if (n->tag == VAL && m->tag == VAL) return val(n->v * m->v);
  if (is_val(n, 0)) return val(0);
  if (is_val(m, 0)) return val(0);
  if (is_val(n, 1)) return inc(m);
  if (is_val(m, 1)) return inc(n);
  if (m->tag == VAL) return tb(mul, val(m->v), n);
  if (n->tag == VAL && m->tag == MUL && m->a->tag == VAL)
    return tb(mul, val(n->v * m->a->v), m->b);
  if (m->tag == MUL && m->a->tag == VAL)
    return tt(mul, val(m->a->v), mul(n, m->b));
  if (n->tag == MUL) { E *t = mul(n->b, m); E *r = mul(n->a, t); dec(t); return r; }
  return mk(MUL, inc(n), inc(m));
}

static E *powr(E *m, E *n) {
  if (m->tag == VAL && n->tag == VAL) return val(pown(m->v, n->v));
  if (is_val(n, 0)) return val(1);
  if (is_val(n, 1)) return inc(m);
  if (is_val(m, 0)) return val(0);
  return mk(POW, inc(m), inc(n));
}

static E *ln(E *n) {
  if (is_val(n, 1)) return val(0);
  return mk(LN, inc(n), NULL);
}

static E *d(const char *x, E *e) {
  switch (e->tag) {
  case VAL: return val(0);
  case VAR: return val(strcmp(x, e->name) == 0 ? 1 : 0);
  case ADD: return tt(add, d(x, e->a), d(x, e->b));
  case MUL: {
    E *f = e->a, *g = e->b;
    return tt(add, bt(mul, f, d(x, g)), bt(mul, g, d(x, f)));
  }
  case POW: {
    E *f = e->a, *g = e->b;
    E *left = tt(mul, bt(mul, g, d(x, f)), bt(powr, f, val(-1)));
    E *right = tt(mul, ln(f), d(x, g));
    return tt(mul, powr(f, g), tt(add, left, right));
  }
  default: { /* LN */
    E *f = e->a;
    return tt(mul, d(x, f), bt(powr, f, val(-1)));
  }
  }
}

static long count(const E *e) {
  long c = 0;
  for (;;) {
    switch (e->tag) {
    case VAL: case VAR: return c + 1;
    case LN: e = e->a; break;
    default: c += count(e->a); e = e->b; break;
    }
  }
}

int main(void) {
  long n = read_int();
  E *x = var("x");
  E *f = powr(x, x);
  dec(x);
  for (long i = 0; i < n; i++) {
    E *f1 = d("x", f);
    printf("%ld count: %ld\n", i + 1, count(f1));
    dec(f);
    f = f1;
  }
  dec(f);
  return 0;
}
