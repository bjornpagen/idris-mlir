/* Compile-time evaluation's arena, as the evaluation child uses it once
 * idris_rt_eval_begin has run: blocks that cross a page of the build's page
 * size (TEST_PAGE_SIZE, from the build, which the runtime checks is the
 * system's), a block that starts a fresh chunk, and one larger than a
 * chunk, each written and read back whole at its ends and at every page
 * boundary inside it; and the cells the runtime makes there. Each check
 * prints one line, the same on every target. */
#include "idris_rt.h"

#include <stdint.h>
#include <stdio.h>

static const size_t page = TEST_PAGE_SIZE;

/* Writes a pattern at both ends of the block and on both sides of every
 * page boundary inside it, then reads it back; the number of boundaries it
 * crossed, or -1 when a byte did not keep its value. */
static long crossing(unsigned char *block, size_t n) {
  uintptr_t base = (uintptr_t)block;
  long boundaries = 0;
  block[0] = 1;
  block[n - 1] = 2;
  for (uintptr_t edge = (base + page) & ~(uintptr_t)(page - 1); edge < base + n; edge += page) {
    size_t at = (size_t)(edge - base);
    block[at - 1] = (unsigned char)(at * 7 + 3);
    block[at] = (unsigned char)(at * 13 + 5);
    ++boundaries;
  }
  if (block[0] != 1 || block[n - 1] != 2)
    return -1;
  for (uintptr_t edge = (base + page) & ~(uintptr_t)(page - 1); edge < base + n; edge += page) {
    size_t at = (size_t)(edge - base);
    if (block[at - 1] != (unsigned char)(at * 7 + 3) || block[at] != (unsigned char)(at * 13 + 5))
      return -1;
  }
  return boundaries;
}

static int aligned(const void *p) { return ((uintptr_t)p & 15) == 0; }

int main(void) {
  idris_rt_eval_begin(2);
  int ok = 1;

  /* Odd small blocks first, so that the next does not start on a page. */
  for (size_t i = 0; i < 7; i++)
    ok &= aligned(idris_rt_arena_alloc(16 + i * 24));
  size_t n = 2 * page + 256;
  unsigned char *across = idris_rt_arena_alloc(n);
  long crossed = crossing(across, n);
  printf("a block of two pages and more, off a page boundary: %s\n",
         crossed >= 2 && aligned(across) ? "keeps its bytes across every page it spans"
                                         : "lost bytes or crossed fewer than two pages");

  /* Blocks of a mebibyte until one does not follow the last: it starts a
   * fresh chunk, which is whole pages too. */
  size_t mebibyte = (size_t)1 << 20;
  unsigned char *last = idris_rt_arena_alloc(mebibyte);
  unsigned char *fresh = NULL;
  for (int i = 0; i < 4096 && fresh == NULL; i++) {
    unsigned char *next = idris_rt_arena_alloc(mebibyte);
    if (next != last + mebibyte)
      fresh = next;
    last = next;
  }
  printf("a block that starts a fresh chunk: %s\n",
         fresh != NULL && ((uintptr_t)fresh & (page - 1)) == 0 && crossing(fresh, mebibyte) > 0
             ? "starts on a page and keeps its bytes"
             : "not found, off a page, or lost bytes");

  /* Larger than a chunk (64 MiB): a chunk of its own, used at its start and
   * across its last pages, which only a block that size reaches. */
  size_t large = ((size_t)65 << 20) + 16;
  unsigned char *big = idris_rt_arena_alloc(large);
  printf("a block larger than a chunk: %s\n",
         aligned(big) && crossing(big, 2 * page) >= 0 &&
                 crossing(big + large - 2 * page - 16, 2 * page + 16) > 0
             ? "keeps its bytes at its start and across its last pages"
             : "lost bytes");

  /* A cell from the arena is persistent (count 0) and a whole block. */
  idris_rt_header *cell = idris_rt_cell(page + 8, 7);
  int cellOk = cell->count == 0 && cell->info == 7 && aligned(cell) &&
               crossing((unsigned char *)cell + sizeof *cell, page) >= 0;
  printf("a cell of more than a page, from the arena: %s\n",
         cellOk ? "persistent, and keeps its bytes" : "not as the arena makes it");

  printf("every block 16-byte aligned: %s\n", ok ? "yes" : "no");
  return 0;
}
