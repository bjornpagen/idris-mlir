/* A compile-time-evaluation arena allocation that crosses a page boundary
 * is usable whole: the arena is reserved address space, committed as it is
 * touched (rt.eval:child), so a block that straddles a page is written and
 * read across it with nothing assuming an allocation ends on a page. The
 * page is the system's (rt.platform::pageSize, the target entry's
 * IDRIS_MLIR_PAGE_SIZE checked at a program's entry); the block is two
 * pages, so its second page is always reached. */
#include "idris_rt.h"

#include <stdint.h>
#include <stdio.h>
#include <unistd.h>

int main(void) {
  size_t page = (size_t)sysconf(_SC_PAGESIZE);
  if (page < 4096) {
    puts("no page size");
    return 1;
  }
  /* Advance the arena by some odd small sizes first, so the block below
   * does not start on the arena's own page boundary. */
  for (size_t i = 0; i < 7; i++) {
    void *small = idris_rt_arena_alloc(16 + i * 24);
    if (small == NULL) {
      puts("no arena");
      return 1;
    }
  }
  size_t n = 2 * page + 256;
  char *p = (char *)idris_rt_arena_alloc(n);
  if (p == NULL) {
    puts("no arena");
    return 1;
  }
  uintptr_t base = (uintptr_t)p;
  uintptr_t boundary = (base + page) & ~(uintptr_t)(page - 1);
  if (boundary <= base || boundary >= base + n) {
    puts("no page boundary inside the block");
    return 1;
  }
  size_t off = (size_t)(boundary - base);
  /* Write across the boundary and read it back, both sides of the page. */
  for (size_t i = off - 8; i < off + 8; i++)
    p[i] = (char)(i * 7 + 1);
  for (size_t i = off - 8; i < off + 8; i++) {
    if (p[i] != (char)(i * 7 + 1)) {
      puts("the block across the boundary did not keep its bytes");
      return 1;
    }
  }
  puts("an arena block keeps its bytes across a page boundary");
  return 0;
}
