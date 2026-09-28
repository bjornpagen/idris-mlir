// What compile-time evaluation's child process adds to the runtime
// (LOW-JIT-1, EVAL-1; docs/cutover.md section 6.4): the arena, which is never
// freed, and the crash report. A crash leaves its call in place; memory the
// machine refuses is EVAL-1.
// PIN(runtime-quarantine) — see PINS.md

#include "internal.h"

#include <sys/mman.h>
#include <unistd.h>

bool rt::arenaActive = false;

namespace {

int reportFd = -1;
char *arenaNext = nullptr;
char *arenaEnd = nullptr;

// Chunks are reserved, not committed: pages cost memory when first touched.
constexpr size_t chunkSize = size_t{1} << 26;

} // namespace

extern "C" void idris_rt_eval_begin(int report_fd) {
  reportFd = report_fd;
  rt::arenaActive = true;
}

extern "C" void *idris_rt_arena_alloc(size_t size) {
  size = (size + 15) & ~size_t{15};
  if (size > static_cast<size_t>(arenaEnd - arenaNext)) {
    size_t chunk = size > chunkSize ? (size + chunkSize - 1) & ~(chunkSize - 1) : chunkSize;
    void *block = mmap(nullptr, chunk, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (block == MAP_FAILED)
      _exit(IDRIS_RT_EVAL_EXHAUSTED);
    arenaNext = static_cast<char *>(block);
    arenaEnd = arenaNext + chunk;
  }
  char *result = arenaNext;
  arenaNext += size;
  return result;
}

extern "C" void idris_rt_eval_crash(const char *msg, size_t len) {
  rt::writeAll(reportFd, msg, len);
  _exit(IDRIS_RT_EVAL_CRASHED);
}
