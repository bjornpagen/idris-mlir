/* A large big's digits are in its cell: its word is the cell's address, even
 * and untagged, and the limbs follow the header and the signed limb count,
 * so they are one load from the word. Each big here is read back through
 * that layout alone and compared with the value it was made from. */
#include <stdio.h>
#include <string.h>

#include "idris_rt.h"

static int failures = 0, checks = 0;

static void check(int ok, const char *what) {
  ++checks;
  if (!ok) {
    fprintf(stderr, "FAIL %s\n", what);
    ++failures;
  }
}

static idris_rt_big parse(const char *s) {
  const idris_rt_str *text = idris_rt_str_from_utf8(s, strlen(s));
  idris_rt_big big = idris_rt_big_from_str(text);
  idris_rt_str_release(text);
  return big;
}

/* The limbs of a large big, read from its word. */
static const uint64_t *limbs(idris_rt_big big) { return (const uint64_t *)((uintptr_t)big + 16); }
static int64_t size(idris_rt_big big) { return ((const idris_rt_bignum *)(uintptr_t)big)->size; }

int main(void) {
  uint64_t before = idris_rt_live_cells();
  /* 2^200 + 5: four limbs, the lowest 5, the highest 2^8. */
  idris_rt_big a = parse("1606938044258990275541962092341162602522202993782792835301381");
  check((a & 1) == 0, "a large big's word is even");
  check(idris_rt_info_kind(((const idris_rt_header *)(uintptr_t)a)->info) == IDRIS_RT_KIND_BIGNUM,
        "its word is the address of a bignum cell");
  check(size(a) == 4, "2^200 + 5 has four limbs");
  check(limbs(a)[0] == 5 && limbs(a)[1] == 0 && limbs(a)[2] == 0 && limbs(a)[3] == 256,
        "its limbs follow the count in the cell");

  /* A result the runtime computes is laid out the same: -2^64 - (2^200 + 5). */
  idris_rt_big b = parse("-18446744073709551616");
  idris_rt_big minusA = idris_rt_big_neg(a);
  idris_rt_big d = idris_rt_big_add(b, minusA);
  check(size(b) == -2 && limbs(b)[0] == 0 && limbs(b)[1] == 1, "-2^64 is two limbs, negative");
  check(size(d) == -4 && limbs(d)[0] == 5 && limbs(d)[1] == 1 && limbs(d)[3] == 256,
        "a sum is written into a cell of its own size");
  idris_rt_big_release(a);
  idris_rt_big_release(b);
  idris_rt_big_release(minusA);
  idris_rt_big_release(d);
  check(idris_rt_live_cells() == before, "a bignum's cell is all it holds: freeing it frees it all");
  printf("big cell: %d of %d checks as idris_rt.h lays a bignum out\n", checks - failures, checks);
  return failures != 0;
}
