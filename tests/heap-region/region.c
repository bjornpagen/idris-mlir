// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
/* Where the runtime's allocator puts cells (rt::alloc, Alloc/Cells.cpp): a
 * heap smaller than 4 GiB lies in one 4 GiB-aligned region, so every cell
 * has the upper 32 bits of every other, and a heap that outgrows the region
 * keeps growing. It runs as a program does, on idris_rt_start, so the
 * runtime reserves its stack before the heap's first cell: cells of sizes
 * from a header and a field up to 4 KiB, between byte arrays of 64 MiB (each
 * one 64 MiB block of the allocator, of which only the first page and the
 * last are touched), to 3 GiB; then 2 GiB more arrays, of which some
 * must lie past the region; then it releases every one, which the checked
 * runtime it links holds it to: a cell still held when the body returns
 * ends the run as the runtime's internal error. */
#include "idris_rt.h"
#include "program.h"

#include <stdint.h>
#include <stdio.h>

#define SIZES 9
#define EACH 2000
#define UNDER 48
#define PAST 32

static const size_t sizes[SIZES] = {16, 24, 32, 48, 64, 128, 256, 1024, 4096};
static const uint64_t arrayBytes = (UINT64_C(64) << 20) - sizeof(idris_rt_array);

static void *cells[SIZES * EACH];
static idris_rt_array *arrays[UNDER + PAST];

static uint64_t regionOf(const void *p) { return (uint64_t)(uintptr_t)p >> 32; }

/* An array whose first and last bytes hold what was written there. */
static int usable(idris_rt_array *a) {
  volatile unsigned char *bytes = (volatile unsigned char *)(a + 1);
  bytes[0] = 1;
  bytes[arrayBytes - 1] = 2;
  return a->length == arrayBytes && bytes[0] == 1 && bytes[arrayBytes - 1] == 2;
}

static void body(void) {
  uint32_t box = idris_rt_info(0, 0, IDRIS_RT_KIND_BOX);
  uint32_t bytes = idris_rt_info(1, 0, IDRIS_RT_KIND_ARRAY);
  size_t made = 0;
  int unusable = 0;
  for (int a = 0; a < UNDER; ++a) {
    for (size_t c = 0; c < SIZES * EACH / UNDER + 1 && made < SIZES * EACH; ++c, ++made)
      cells[made] = idris_rt_cell(sizes[made % SIZES], box);
    arrays[a] = idris_rt_array_new_unwritten(arrayBytes, bytes);
    unusable += !usable(arrays[a]);
  }
  uint64_t region = regionOf(cells[0]);
  size_t outside = 0;
  for (size_t c = 0; c < made; ++c)
    outside += regionOf(cells[c]) != region;
  for (int a = 0; a < UNDER; ++a)
    outside += regionOf(arrays[a]) != region;
  printf("under 4 GiB: %d arrays of 64 MiB and %zu cells, %zu outside the first cell's 4 GiB "
         "region\n",
         UNDER, made, outside);
  /* The region is left only once the heap is past it: 5 GiB of arrays
   * cannot all lie in one 4 GiB region, so some must be outside it, which
   * shows the count above can see an address that is. */
  size_t past = 0;
  for (int a = UNDER; a < UNDER + PAST; ++a) {
    arrays[a] = idris_rt_array_new_unwritten(arrayBytes, bytes);
    unusable += !usable(arrays[a]);
    past += regionOf(arrays[a]) != region;
  }
  printf("past 4 GiB: %d more arrays of 64 MiB, %s outside the first cell's region; arrays whose bytes "
         "did not hold: %d\n",
         PAST, past > 0 ? "some" : "none", unusable);
  fflush(stdout);
  for (size_t c = 0; c < made; ++c)
    idris_rt_dec_cell(cells[c]);
  for (int a = 0; a < UNDER + PAST; ++a)
    idris_rt_dec_cell(&arrays[a]->header);
}

/* The body's frames and the C library's printf, well within it. */
IDRIS_RT_TEST_PROGRAM("region", 256 * 1024);

int main(int argc, char **argv) { idris_rt_test_start(body, argc, argv); }
