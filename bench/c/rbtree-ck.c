/* Red-black tree insertion with checkpoints, as Main.idr here (Perceus's
   rbtree-ck.kk), in C. The trees share cells, so each cell carries a count:
   insertion updates a cell in place when the count is one and copies it
   otherwise (copy-on-write), which is what reference counting with reuse
   does in Lean and Koka. */
#include <stdio.h>
#include <stdlib.h>

enum { RED, BLACK };

typedef struct Node {
  long rc;
  struct Node *l, *r;
  long key;
  unsigned char color, val;
} Node;

typedef struct List {
  Node *head;
  struct List *tail;
} List;

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static void inc(Node *t) { if (t) t->rc++; }

static void dec(Node *t) {
  while (t && --t->rc == 0) {
    Node *r = t->r;
    dec(t->l);
    free(t);
    t = r;
  }
}

/* Returns a cell with t's contents that the caller owns alone. */
static Node *uniq(Node *t) {
  if (t->rc == 1) return t;
  Node *c = malloc(sizeof *c);
  *c = *t;
  c->rc = 1;
  inc(c->l);
  inc(c->r);
  t->rc--;
  return c;
}

static int is_red(const Node *t) { return t && t->color == RED; }

/* balance1 kv vv t n, with n non-empty: s holds Black kv vv t in its fields
   (s->r = t), and s and n are owned alone. */
static Node *balance1(Node *s, Node *n) {
  if (is_red(n->l)) {         /* Node _ (Node Red l kx vx r1) ky vy r2 */
    Node *nl = n->l = uniq(n->l);
    nl->color = BLACK;
    s->l = n->r;
    n->color = RED; n->l = nl; n->r = s;
    return n;
  }
  if (is_red(n->r)) {         /* Node _ l1 ky vy (Node Red l2 kx vx r) */
    Node *nr = uniq(n->r);
    n->color = BLACK; n->r = nr->l;
    s->l = nr->r;
    nr->color = RED; nr->l = n; nr->r = s;
    return nr;
  }
  n->color = RED;             /* Node _ l ky vy r */
  s->l = n;
  return s;
}

/* balance2 t kv vv n, with n non-empty: s holds Black t kv vv (s->l = t). */
static Node *balance2(Node *s, Node *n) {
  if (is_red(n->l)) {         /* Node _ (Node Red l kx1 vx1 r1) ky vy r2 */
    Node *nl = uniq(n->l);
    s->r = nl->l;
    n->color = BLACK; n->l = nl->r;
    nl->color = RED; nl->l = s; nl->r = n;
    return nl;
  }
  if (is_red(n->r)) {         /* Node _ l1 ky vy (Node Red l2 kx2 vx2 r2) */
    Node *nr = n->r = uniq(n->r);
    s->r = n->l;
    nr->color = BLACK;
    n->color = RED; n->l = s; n->r = nr;
    return n;
  }
  n->color = RED;             /* Node _ l ky vy r */
  s->r = n;
  return s;
}

/* ins t kx vx, consuming the caller's reference to t. */
static Node *ins(Node *t, long kx, int vx) {
  if (!t) {
    Node *n = malloc(sizeof *n);
    n->rc = 1; n->l = n->r = NULL; n->key = kx; n->val = (unsigned char)vx; n->color = RED;
    return n;
  }
  t = uniq(t);
  if (t->color == RED) {
    if (kx < t->key) t->l = ins(t->l, kx, vx);
    else if (kx == t->key) { t->key = kx; t->val = (unsigned char)vx; }
    else t->r = ins(t->r, kx, vx);
    return t;
  }
  if (kx < t->key) {
    if (is_red(t->l)) return balance1(t, ins(t->l, kx, vx));
    t->l = ins(t->l, kx, vx);
    return t;
  }
  if (kx == t->key) { t->key = kx; t->val = (unsigned char)vx; return t; }
  if (is_red(t->r)) return balance2(t, ins(t->r, kx, vx));
  t->r = ins(t->r, kx, vx);
  return t;
}

static Node *insert(Node *t, long k, int v) {
  if (is_red(t)) {
    t = ins(t, k, v);
    t->color = BLACK;   /* ins returned a cell owned alone */
    return t;
  }
  return ins(t, k, v);
}

static long fold(const Node *t, long b) {
  while (t) {
    b = fold(t->l, b) + (t->val ? 1 : 0);
    t = t->r;
  }
  return b;
}

int main(void) {
  long n = read_int();
  const long freq = 5;
  Node *t = NULL;
  List *acc = NULL;
  for (long i = n; i > 0; i--) {
    t = insert(t, i, i % 10 == 0);
    if (i % freq == 0) {
      List *c = malloc(sizeof *c);
      inc(t);
      c->head = t; c->tail = acc;
      acc = c;
    }
  }
  List *c = malloc(sizeof *c);
  c->head = t; c->tail = acc;   /* the list takes the last reference to t */
  acc = c;
  long len = 0;
  for (List *p = acc; p; p = p->tail) len += p->head != NULL;
  printf("%ld %ld\n", len, fold(acc->head, 0));
  while (acc) {
    List *next = acc->tail;
    dec(acc->head);
    free(acc);
    acc = next;
  }
  return 0;
}
