// Every allocation of a tool, on Tracy's memory timeline: the global
// operator new and delete, every replaceable form, through malloc and free
// with Tracy told of each. Compiled into the three tools only, and only in
// a profile build configured with IDRIS_MLIR_PROFILE_MEMORY: no library
// holds these, so nothing that links a library of ours gets them, and a
// profile of time is not slowed by a lock per allocation, which across
// MLIR's threads would distort the timeline it is for.
//
// Tracy asks nothing of an allocation made before the profiler starts or
// after it stops, and until a capture connects (TRACY_ON_DEMAND) each call
// costs a load and a branch; a free of a block allocated before the
// capture connected is one Tracy has not seen, which an on-demand capture
// ignores. Tracy's own memory comes from its own allocator, never from
// here.

#ifndef TRACY_ENABLE
#error "ProfileAlloc.cpp is part of the profile build only (IDRIS_MLIR_PROFILE_MEMORY needs IDRIS_MLIR_PROFILE)"
#endif

#include "idr/Support/Profile.h"

#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <new>

namespace {

// A block of at least `size` bytes at `alignment`, or null. Every form of
// new comes here, so every block is one free releases.
void *allocate(std::size_t size, std::size_t alignment) {
  // A new of zero bytes still returns a block of its own.
  size = std::max<std::size_t>(size, 1);
  void *block = nullptr;
  if (alignment <= alignof(std::max_align_t)) {
    block = std::malloc(size);
  } else if (posix_memalign(&block, std::max(alignment, sizeof(void *)), size) != 0) {
    block = nullptr;
  }
  if (block)
    TracyAlloc(block, size);
  return block;
}

// The throwing forms. The tools are built without exceptions, so a failure
// the new handler cannot mend ends the process.
void *allocateOrAbort(std::size_t size, std::size_t alignment) {
  for (;;) {
    if (void *block = allocate(size, alignment))
      return block;
    std::new_handler handler = std::get_new_handler();
    if (!handler)
      std::abort();
    handler();
  }
}

void release(void *block) noexcept {
  if (!block)
    return;
  TracyFree(block);
  std::free(block);
}

constexpr std::size_t plain = alignof(std::max_align_t);

std::size_t aligned(std::align_val_t alignment) { return static_cast<std::size_t>(alignment); }

} // namespace

void *operator new(std::size_t size) { return allocateOrAbort(size, plain); }
void *operator new[](std::size_t size) { return allocateOrAbort(size, plain); }
void *operator new(std::size_t size, const std::nothrow_t &) noexcept { return allocate(size, plain); }
void *operator new[](std::size_t size, const std::nothrow_t &) noexcept { return allocate(size, plain); }
void *operator new(std::size_t size, std::align_val_t alignment) { return allocateOrAbort(size, aligned(alignment)); }
void *operator new[](std::size_t size, std::align_val_t alignment) {
  return allocateOrAbort(size, aligned(alignment));
}
void *operator new(std::size_t size, std::align_val_t alignment, const std::nothrow_t &) noexcept {
  return allocate(size, aligned(alignment));
}
void *operator new[](std::size_t size, std::align_val_t alignment, const std::nothrow_t &) noexcept {
  return allocate(size, aligned(alignment));
}

void operator delete(void *block) noexcept { release(block); }
void operator delete[](void *block) noexcept { release(block); }
void operator delete(void *block, std::size_t) noexcept { release(block); }
void operator delete[](void *block, std::size_t) noexcept { release(block); }
void operator delete(void *block, const std::nothrow_t &) noexcept { release(block); }
void operator delete[](void *block, const std::nothrow_t &) noexcept { release(block); }
void operator delete(void *block, std::align_val_t) noexcept { release(block); }
void operator delete[](void *block, std::align_val_t) noexcept { release(block); }
void operator delete(void *block, std::size_t, std::align_val_t) noexcept { release(block); }
void operator delete[](void *block, std::size_t, std::align_val_t) noexcept { release(block); }
void operator delete(void *block, std::align_val_t, const std::nothrow_t &) noexcept { release(block); }
void operator delete[](void *block, std::align_val_t, const std::nothrow_t &) noexcept { release(block); }
