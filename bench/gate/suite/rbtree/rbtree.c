/* Red-black tree insertion, as Main.idr here (Perceus's rbtree.kk), in C.
   The tree is never shared, so every node the functional version rebuilds
   is updated in place: this is what full reuse achieves, and the floor for
   the functional versions. */
#include <stdio.h>
#include <stdlib.h>

enum { RED, BLACK };

typedef struct Node {
  struct Node *l, *r;
  long key;
  unsigned char color, val;
} Node;

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static int is_red(const Node *t) { return t && t->color == RED; }

/* balanceLeft (ins l) k v r, where t holds Black k v r and l is non-empty. */
static Node *balance_left(Node *l, Node *t) {
  if (is_red(l->l)) {           /* Node _ (Node Red lx kx vx rx) ky vy ry */
    Node *ll = l->l;
    ll->color = BLACK;
    t->l = l->r;
    l->color = RED; l->l = ll; l->r = t;
    return l;
  }
  if (is_red(l->r)) {           /* Node _ ly ky vy (Node Red lx kx vx rx) */
    Node *lr = l->r;
    l->color = BLACK; l->r = lr->l;
    t->l = lr->r;
    lr->color = RED; lr->l = l; lr->r = t;
    return lr;
  }
  l->color = RED;               /* Node _ lx kx vx rx */
  t->l = l;
  return t;
}

/* balanceRight l k v (ins r), where t holds Black l k v and r is non-empty. */
static Node *balance_right(Node *t, Node *r) {
  if (is_red(r->l)) {           /* Node _ (Node Red lx kx vx rx) ky vy ry */
    Node *rl = r->l;
    t->r = rl->l;
    r->color = BLACK; r->l = rl->r;
    rl->color = RED; rl->l = t; rl->r = r;
    return rl;
  }
  if (is_red(r->r)) {           /* Node _ lx kx vx (Node Red ly ky vy ry) */
    Node *rr = r->r;
    t->r = r->l;
    rr->color = BLACK;
    r->color = RED; r->l = t; r->r = rr;
    return r;
  }
  r->color = RED;               /* Node _ lx kx vx rx */
  t->r = r;
  return t;
}

static Node *ins(Node *t, long k, int v) {
  if (!t) {
    Node *n = malloc(sizeof *n);
    n->l = n->r = NULL; n->key = k; n->val = (unsigned char)v; n->color = RED;
    return n;
  }
  if (t->color == RED) {
    if (k < t->key) t->l = ins(t->l, k, v);
    else if (k > t->key) t->r = ins(t->r, k, v);
    else { t->key = k; t->val = (unsigned char)v; }
    return t;
  }
  if (k < t->key) {
    if (is_red(t->l)) return balance_left(ins(t->l, k, v), t);
    t->l = ins(t->l, k, v);
    return t;
  }
  if (k > t->key) {
    if (is_red(t->r)) return balance_right(t, ins(t->r, k, v));
    t->r = ins(t->r, k, v);
    return t;
  }
  t->key = k; t->val = (unsigned char)v;
  return t;
}

static Node *insert(Node *t, long k, int v) {
  t = ins(t, k, v);
  t->color = BLACK;
  return t;
}

static long fold(const Node *t, long b) {
  while (t) {
    b = fold(t->l, b) + (t->val ? 1 : 0);
    t = t->r;
  }
  return b;
}

static void drop(Node *t) {
  while (t) {
    Node *r = t->r;
    drop(t->l);
    free(t);
    t = r;
  }
}

int main(void) {
  long n = read_int();
  Node *t = NULL;
  for (long i = n; i > 0; i--) t = insert(t, i - 1, (i - 1) % 10 == 0);
  printf("%ld\n", fold(t, 0));
  drop(t);
  return 0;
}
