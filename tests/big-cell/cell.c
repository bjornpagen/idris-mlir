// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* A large big's digits are in its cell: its word is the cell's address, even
 * and untagged, and the limbs follow the header and the signed limb count,
 * so they are one load from the word. Both ways: each big the runtime makes
 * is read back through that layout alone and compared with the value it
 * was made from, at the small range's edges (where the word turns from
 * odd to even), the limb's (2^64 - 1, 2^64) and past; and a cell the test
 * lays out itself is read by the runtime as its value, while the same cell
 * with its lowest limb one off is not, so the comparison could fail. It
 * runs as a program on the checked runtime, whose count of the cells it
 * holds shows each big's cell is all it holds. */
#include <stdio.h>
#include <string.h>

#include "idris_rt.h"
#include "program.h"

static int failures = 0;

static void check(int ok, const char *what, const char *text) {
  if (!ok) {
    printf("big cell: fails: %s: %s\n", text, what);
    ++failures;
  }
}

static idris_rt_big parse(const char *s) {
  const idris_rt_str *text = idris_rt_str_from_utf8(s, strlen(s));
  idris_rt_big big = idris_rt_big_from_str(text);
  idris_rt_dec_cell((void *)text);
  return big;
}

/* The limbs of a large big, read from its word: they follow the cell's
 * header and limb count, idris_rt_bignum, in the same cell. */
static const uint64_t *limbs(idris_rt_big big) {
  return (const uint64_t *)((const idris_rt_bignum *)(uintptr_t)big + 1);
}
static int64_t size(idris_rt_big big) { return ((const idris_rt_bignum *)(uintptr_t)big)->size; }

/* A value: its decimal text, and either the small value its odd word holds
 * or its signed limb count and its limbs, least significant first. */
struct value {
  const char *text;
  int small;
  int64_t word;
  int64_t size;
  uint64_t limbs[4];
};
static const struct value values[] = {
    {"0", 1, 0, 0, {0}},
    {"4611686018427387903", 1, IDRIS_RT_SMALL_MAX, 0, {0}},
    {"-4611686018427387904", 1, IDRIS_RT_SMALL_MIN, 0, {0}},
    /* Just past the small range, either way: one limb each. */
    {"4611686018427387904", 0, 0, 1, {UINT64_C(1) << 62}},
    {"-4611686018427387905", 0, 0, -1, {(UINT64_C(1) << 62) + 1}},
    /* The limb's edge: its largest value, then two limbs. */
    {"18446744073709551615", 0, 0, 1, {UINT64_MAX}},
    {"18446744073709551616", 0, 0, 2, {0, 1}},
    {"-18446744073709551616", 0, 0, -2, {0, 1}},
    /* 2^200 + 5: four limbs, the lowest 5, the highest 2^8. */
    {"1606938044258990275541962092341162602522202993782792835301381", 0, 0, 4, {5, 0, 0, 256}},
};

/* A persistent big laid out by the test as idris_rt.h lays one out (and
 * idr-lower writes one into static data): count 0, a bignum's info, the
 * signed limb count, the limbs. */
struct constant {
  idris_rt_bignum cell;
  uint64_t limbs[4];
};

/* The runtime's decimal text of `big` is `text`. */
static int shows(idris_rt_big big, const char *text) {
  const idris_rt_str *shown = idris_rt_big_show(big);
  int same = shown->bytes == strlen(text) && memcmp(idris_rt_str_bytes(shown), text, shown->bytes) == 0;
  idris_rt_dec_cell((void *)shown);
  return same;
}

static void checkValue(const struct value *v) {
  idris_rt_big b = parse(v->text);
  if (v->small) {
    check(idris_rt_word_is_small(b) && idris_rt_small_value(b) == v->word, "a small value's word is odd and holds it",
          v->text);
    idris_rt_dec_big(b);
    return;
  }
  check(!idris_rt_word_is_small(b), "a large big's word is even", v->text);
  check(idris_rt_info_kind(((const idris_rt_header *)(uintptr_t)b)->info) == IDRIS_RT_KIND_BIGNUM,
        "its word is the address of a bignum cell", v->text);
  int64_t n = v->size < 0 ? -v->size : v->size;
  check(size(b) == v->size, "its signed limb count follows the header", v->text);
  int same = size(b) == v->size;
  for (int64_t i = 0; same && i < n; ++i)
    same = limbs(b)[i] == v->limbs[i];
  check(same, "its limbs follow the count in the cell", v->text);

  struct constant c = {{{0, idris_rt_info(0, 0, IDRIS_RT_KIND_BIGNUM)}, v->size}, {0}};
  memcpy(c.limbs, v->limbs, sizeof c.limbs);
  idris_rt_big laid = (idris_rt_big)(uintptr_t)&c;
  check(idris_rt_big_cmp(laid, b) == 0 && shows(laid, v->text), "the runtime reads the test's cell as the value",
        v->text);
  c.limbs[0] ^= 1;
  check(idris_rt_big_cmp(laid, b) != 0 && !shows(laid, v->text),
        "the runtime reads the test's cell with its lowest limb one off as another value", v->text);
  idris_rt_dec_big(b);
}

static void body(void) {
  uint64_t before = prop_held();
  for (size_t i = 0; i < sizeof values / sizeof values[0]; ++i)
    checkValue(&values[i]);

  /* A result the runtime computes is laid out the same: -2^64 - (2^200 + 5),
   * and 2^62 - 1 + 1, which leaves the small range. */
  idris_rt_big a = parse(values[8].text);
  idris_rt_big b = parse("-18446744073709551616");
  idris_rt_big minusA = idris_rt_big_neg(a);
  idris_rt_big d = idris_rt_big_add(b, minusA);
  check(size(d) == -4 && limbs(d)[0] == 5 && limbs(d)[1] == 1 && limbs(d)[2] == 0 && limbs(d)[3] == 256,
        "a sum is written into a cell of its own size", "-2^64 - (2^200 + 5)");
  idris_rt_big top = parse(values[1].text), one = parse("1");
  idris_rt_big past = idris_rt_big_add(top, one);
  check(!idris_rt_word_is_small(past) && size(past) == 1 && limbs(past)[0] == UINT64_C(1) << 62,
        "a sum past the small range is a cell of one limb", "2^62 - 1 + 1");
  idris_rt_dec_big(a);
  idris_rt_dec_big(b);
  idris_rt_dec_big(minusA);
  idris_rt_dec_big(d);
  idris_rt_dec_big(top);
  idris_rt_dec_big(one);
  idris_rt_dec_big(past);
  check(prop_held() == before, "a bignum's cell is all it holds: freeing it frees it all", "every big");
  if (failures == 0)
    printf("big cell: every check holds as idris_rt.h lays a bignum out\n");
  fflush(stdout);
  if (failures != 0)
    idris_rt_exit(1);
}

/* A few frames of its own, and the C library's printf. */
IDRIS_RT_TEST_PROGRAM("cell", 256 * 1024);

int main(int argc, char **argv) { idris_rt_test_start(body, argc, argv); }
