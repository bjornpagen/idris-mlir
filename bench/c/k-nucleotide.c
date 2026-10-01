/* k-nucleotide on one core, as Main.idr here: the third sequence's
   fragments counted in an open-addressing hash table keyed by the
   fragment packed two bits a nucleotide. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { unsigned long long key; long count; int used; } Slot;
typedef struct { Slot *slots; size_t mask; } Table;

static Table table_new(size_t n) {
  size_t cap = 1;
  while (cap < 2 * n) cap <<= 1;
  Table t = {calloc(cap, sizeof(Slot)), cap - 1};
  return t;
}

static long *table_at(Table *t, unsigned long long key) {
  size_t i = (key * 0x9E3779B97F4A7C15ull) & t->mask;
  while (t->slots[i].used && t->slots[i].key != key) i = (i + 1) & t->mask;
  if (!t->slots[i].used) { t->slots[i].used = 1; t->slots[i].key = key; }
  return &t->slots[i].count;
}

static int code(char c) { return (c >> 1) & 3; } /* A 0, C 1, T 2, G 3 */
static const char letters[] = "ACTG";

static unsigned long long pack(const char *s, int k) {
  unsigned long long key = 0;
  for (int i = 0; i < k; i++) key = key * 4 + code(s[i]);
  return key;
}

static Table count(const char *seq, long len, int k) {
  long n = len - k + 1;
  Table t = table_new(n < 4096 ? 4096 : n);
  unsigned long long key = 0, mask = k == 32 ? ~0ull : (1ull << (2 * k)) - 1;
  for (long i = 0; i < len; i++) {
    key = ((key << 2) | code(seq[i])) & mask;
    if (i >= k - 1) (*table_at(&t, key))++;
  }
  return t;
}

typedef struct { char name[3]; long count; } Freq;
static int by_frequency(const void *a, const void *b) {
  const Freq *x = a, *y = b;
  if (x->count != y->count) return x->count < y->count ? 1 : -1;
  return strcmp(x->name, y->name);
}

static void frequencies(const char *seq, long len, int k) {
  Table t = count(seq, len, k);
  Freq f[16];
  int n = 0;
  for (int i = 0; i < (1 << (2 * k)); i++) {
    unsigned long long key = i;
    for (int j = k - 1; j >= 0; j--) { f[n].name[j] = letters[key & 3]; key >>= 2; }
    f[n].name[k] = 0;
    f[n].count = *table_at(&t, i);
    n++;
  }
  qsort(f, n, sizeof *f, by_frequency);
  for (int i = 0; i < n; i++) printf("%s %.3f\n", f[i].name, 100.0 * f[i].count / (len - k + 1));
  puts("");
  free(t.slots);
}

static void fragment(const char *seq, long len, const char *frag) {
  int k = (int)strlen(frag);
  Table t = count(seq, len, k);
  printf("%ld\t%s\n", *table_at(&t, pack(frag, k)), frag);
  free(t.slots);
}

int main(void) {
  char *line = NULL;
  size_t cap = 0;
  ssize_t got;
  while ((got = getline(&line, &cap, stdin)) > 0)
    if (strncmp(line, ">THREE", 6) == 0) break;
  size_t scap = 1 << 20, len = 0;
  char *seq = malloc(scap);
  while ((got = getline(&line, &cap, stdin)) > 0) {
    if (line[0] == '>') break;
    if (line[got - 1] == '\n') got--;
    if (len + got > scap) { scap = 2 * (len + got); seq = realloc(seq, scap); }
    for (ssize_t i = 0; i < got; i++) seq[len++] = (char)(line[i] & ~0x20);
  }
  frequencies(seq, len, 1);
  frequencies(seq, len, 2);
  const char *frags[] = {"GGT", "GGTA", "GGTATT", "GGTATTTTAATT", "GGTATTTTAATTTATAGT"};
  for (int i = 0; i < 5; i++) fragment(seq, len, frags[i]);
  return 0;
}
