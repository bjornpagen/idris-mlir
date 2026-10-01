/* Union-find with path compression and union by rank, as Main.idr here
   (Lean's unionfind.lean), in C: the records are stored in the array. */
#include <stdio.h>
#include <stdlib.h>

typedef struct { long find, rank; } NodeData;

static NodeData *s;
static long cap;

static long read_int(void) {
  long n = 0;
  int c;
  while ((c = getchar()) >= '0' && c <= '9') n = n * 10 + (c - '0');
  return n;
}

static void fail(const char *e) {
  printf("Error : %s\n", e);
  exit(1);
}

static NodeData find_entry_aux(long fuel, long n) {
  if (fuel == 0) fail("out of fuel");
  if (n < 0 || n >= cap) fail("invalid Node");
  NodeData e = s[n];
  if (e.find == n) return e;
  NodeData e1 = find_entry_aux(fuel - 1, e.find);
  s[n] = e1;
  return e1;
}

static NodeData find_entry(long n) { return find_entry_aux(cap, n); }

static void unite(long n1, long n2) {
  NodeData r1 = find_entry(n1), r2 = find_entry(n2);
  if (r1.find == r2.find) return;
  if (r1.rank < r2.rank) s[r1.find] = (NodeData){r2.find, 0};
  else if (r1.rank == r2.rank) {
    s[r1.find] = (NodeData){r2.find, 0};
    s[r2.find] = (NodeData){r2.find, r2.rank + 1};
  } else s[r2.find] = (NodeData){r1.find, 0};
}

static void merge_pack(long d) {
  for (long fuel = cap, n = 0; fuel != 0 && n + d < cap; fuel--, n++) unite(n, n + d);
}

static long num_eqs(void) {
  long r = 0;
  for (long fuel = cap, n = 0; fuel != 0 && n < cap; fuel--, n++)
    if (find_entry(n).find != n) r++;
  return r;
}

int main(void) {
  long n = read_int();
  if (n < 2) fail("input must be greater than 1");
  cap = n;
  s = malloc((size_t)n * sizeof *s);
  for (long i = 0; i < n; i++) s[i] = (NodeData){i, 1};
  merge_pack(50000);
  merge_pack(10000);
  merge_pack(5000);
  merge_pack(1000);
  printf("ok %ld\n", num_eqs());
  free(s);
  return 0;
}
