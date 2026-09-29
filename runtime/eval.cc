// What compile-time evaluation's child process adds to the runtime: the
// arena, which is never freed, the crash report, and the meter of a call
// that need not end. A crash leaves its call in place; memory the machine
// refuses is reported as exhaustion.
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

// The meter of the running call, when it is metered: the ticks and arena
// bytes it has left, and the lowest address its stack may reach.
bool metered = false;
uint64_t ticksLeft = 0;
size_t bytesLeft = 0;
uintptr_t stackFloor = 0;

[[noreturn]] void overBudget() { _exit(IDRIS_RT_EVAL_OVER_BUDGET); }

} // namespace

extern "C" void idris_rt_eval_begin(int report_fd) {
  reportFd = report_fd;
  rt::arenaActive = true;
}

extern "C" void idris_rt_eval_meter(uint64_t ticks, uint64_t bytes, uint64_t stack) {
  metered = true;
  ticksLeft = ticks;
  bytesLeft = bytes;
  auto here = reinterpret_cast<uintptr_t>(__builtin_frame_address(0));
  stackFloor = here > stack ? here - stack : 0;
}

extern "C" void idris_rt_eval_unmetered(void) { metered = false; }

extern "C" void idris_rt_eval_tick(void) {
  if (!metered)
    return;
  if (ticksLeft == 0 || reinterpret_cast<uintptr_t>(__builtin_frame_address(0)) < stackFloor)
    overBudget();
  --ticksLeft;
}

extern "C" void *idris_rt_arena_alloc(size_t size) {
  size = (size + 15) & ~size_t{15};
  if (metered) {
    if (size > bytesLeft)
      overBudget();
    bytesLeft -= size;
  }
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
