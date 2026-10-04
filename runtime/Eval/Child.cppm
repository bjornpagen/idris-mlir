// rt.eval:child: what compile-time evaluation's child process adds to the
// runtime: the arena, which is never freed, the crash report, and the meter
// of a call that need not end. A crash leaves its call in place; memory the
// machine refuses is reported as exhaustion.
//
// Only the compiler calls these entry points, natively (the child is
// idris-mlir-cc itself, and the code it JITs binds them by address); no
// program does. Each is annotated so, and idris-mlir-cc keeps them out of
// the runtime it prepares for programs, where the arena is then never
// active and every allocation knows it.
// PIN(runtime-quarantine) — see PINS.md
module;
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <unistd.h>

#define IDRIS_RT_COMPILER_ONLY [[clang::annotate("idris-rt-compiler")]]

export module rt.eval:child;

import rt.alloc;
import rt.io;
import rt.platform;

namespace {

int reportFd = -1;
char *arenaNext = nullptr;
char *arenaEnd = nullptr;

// Chunks are reserved, not committed: pages cost memory when first touched.
// The size is a multiple of 64 MiB, and reserve() maps whole pages of
// whatever the system's page size is (rt.platform), so this bounds how much
// address space a chunk asks for, not a page-aligned quantity of its own.
// A block is 16-byte aligned and may span pages, never chunks: one larger
// than a chunk gets one of its own, of whole chunks.
constexpr size_t chunkSize = size_t{1} << 26;
static_assert(chunkSize % IDRIS_RT_PAGE_SIZE == 0, "a chunk is whole pages");

// The meter of the running call, when it is metered: the ticks and arena
// bytes it has left, and the lowest address its stack may reach.
bool metered = false;
uint64_t ticksLeft = 0;
size_t bytesLeft = 0;
uintptr_t stackFloor = 0;

[[noreturn]] void overBudget() { _exit(IDRIS_RT_EVAL_OVER_BUDGET); }

} // namespace

extern "C" IDRIS_RT_COMPILER_ONLY void idris_rt_eval_begin(int report_fd) {
  reportFd = report_fd;
  rt::alloc::arenaActive = true;
}

extern "C" IDRIS_RT_COMPILER_ONLY void idris_rt_eval_meter(uint64_t ticks, uint64_t bytes,
                                                        uint64_t stack) {
  metered = true;
  ticksLeft = ticks;
  bytesLeft = bytes;
  auto here = reinterpret_cast<uintptr_t>(__builtin_frame_address(0));
  stackFloor = here > stack ? here - stack : 0;
}

extern "C" IDRIS_RT_COMPILER_ONLY void idris_rt_eval_unmetered(void) { metered = false; }

extern "C" IDRIS_RT_COMPILER_ONLY void idris_rt_eval_tick(void) {
  if (!metered)
    return;
  if (ticksLeft == 0 || reinterpret_cast<uintptr_t>(__builtin_frame_address(0)) < stackFloor)
    overBudget();
  --ticksLeft;
}

extern "C" IDRIS_RT_COMPILER_ONLY void *idris_rt_arena_alloc(size_t size) {
  // No machine grants this much, and rounding it up below would wrap around
  // to a small block.
  if (size > SIZE_MAX - chunkSize)
    _exit(IDRIS_RT_EVAL_EXHAUSTED);
  size = (size + 15) & ~size_t{15};
  if (metered) {
    if (size > bytesLeft)
      overBudget();
    bytesLeft -= size;
  }
  if (size > static_cast<size_t>(arenaEnd - arenaNext)) {
    size_t chunk = size > chunkSize ? (size + chunkSize - 1) & ~(chunkSize - 1) : chunkSize;
    char *block = rt::platform::reserve(chunk);
    if (block == nullptr)
      _exit(IDRIS_RT_EVAL_EXHAUSTED);
    arenaNext = block;
    arenaEnd = arenaNext + chunk;
  }
  char *result = arenaNext;
  arenaNext += size;
  return result;
}

extern "C" IDRIS_RT_COMPILER_ONLY void idris_rt_eval_crash(const char *msg, size_t len) {
  rt::io::writeAll(reportFd, msg, len);
  _exit(IDRIS_RT_EVAL_CRASHED);
}
