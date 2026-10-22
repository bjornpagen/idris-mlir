// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's memory over snmalloc: the heap's span, raw blocks, and
// cells. snmalloc is included here alone, so its fast paths inline into
// newCell and freeCell in every build. Those two, the allocation under them
// and idris_rt_cell are always inlined wherever the runtime's bitcode is
// joined, every program among them: idr-lower calls idris_rt_cell with a
// constant size, so the size class folds and an allocation is a
// thread-local free-list pop in the caller, whatever the inliner's budget
// says. A unit compiled alone calls them.
//
// snmalloc is the copy the bootstrap exports with its patches, configured
// as its own build describes it (runtime/CMakeLists.txt): size classes
// that step by 8 bytes, so a cell of an 8-byte header and two fields takes
// exactly 24; the target entry's page; its own small STL; no thread
// teardown of its own; and exactly one mitigation, the one that keeps a
// reservation inaccessible until it is committed, a commit that a strict
// host refuses being then a refusal, never memory handed out unusable. Its
// configuration is HeapConfig below, composed from snmalloc's parts as its
// own configurations are, whose source of chunks is the span.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "End/End.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>
#include <string.h>

#include <snmalloc/backend/fixedglobalconfig.h>
#include <snmalloc/snmalloc_core.h>

namespace rt::alloc {

// The heap's chunks lie in one span, from an address aligned to 4 GiB,
// reserved in address order as snmalloc asks for them, so every cell of a
// heap smaller than 4 GiB has the same upper 32 bits as every other. That is
// what a data memory-dependent prefetcher asks of a word before it follows
// it (Apple's, which scans each cache line a load fills and fetches what a
// word in it points to, only when the word and its address share their
// 4 GiB region). Only the alignment is the prefetcher's: nothing of the
// region is reserved before it is used, which costs nothing on a target
// with no such prefetcher.
inline constexpr size_t regionBits = 32;

// snmalloc's POSIX or Apple platform, whose fatal errors (its own state
// refused, a range it was handed out of bounds) end the process as the
// runtime's internal error, the output written first, rather than its
// unflushed abort in another format.
struct Pal : snmalloc::DefaultPal {
  [[noreturn]] static void error(const char *const text) noexcept {
    rt::end::end(rt::end::AllocatorFailed{text});
  }
};

// The span: chunks reserved at fixed addresses, in order, from the cursor
// up, each aligned to its size as snmalloc asks; a mapping already there
// (the C library's, the program's image) is stepped past. The system
// refusing address space, or the span's end, is a null, which snmalloc
// meets as out of memory. Under the global range's lock, as every source of
// snmalloc's backend is.
class SpanRange {
public:
  static constexpr bool Aligned = true;
  static constexpr bool ConcurrencySafe = false;
  using ChunkBounds = snmalloc::capptr::bounds::Arena;

  constexpr SpanRange() = default;

  // The span, from the first byte past the page map to its end.
  static void set(uintptr_t from, uintptr_t to) noexcept {
    cursor = from;
    end = to;
  }

  // `size` bytes at the cursor, aligned to `alignment`: a chunk, or the
  // runner's stacks before any chunk. The walk ends at the span's end, or
  // where rounding up wraps: a mapping already there moves the cursor past
  // the chunk it is in the way of, so every step is higher.
  static char *take(size_t size, size_t alignment) noexcept {
    for (uintptr_t at = rt::platform::roundUp(cursor, alignment);
         at >= cursor && at <= end && end - at >= size;
         at = rt::platform::roundUp(cursor, alignment)) {
      switch (rt::platform::reserveAt(reinterpret_cast<char *>(at), size)) {
      case rt::platform::Placed::Reserved:
        cursor = at + size;
        return reinterpret_cast<char *>(at);
      case rt::platform::Placed::Occupied:
        cursor = at + size;
        continue;
      case rt::platform::Placed::Refused:
        return nullptr;
      }
    }
    return nullptr;
  }

  snmalloc::capptr::Arena<void> alloc_range(size_t size) {
    return snmalloc::capptr::Arena<void>::unsafe_from(take(size, size));
  }

private:
  SNMALLOC_REQUIRE_CONSTINIT inline static uintptr_t cursor = 0;
  SNMALLOC_REQUIRE_CONSTINIT inline static uintptr_t end = 0;
};

// The host's limit on committed memory, after snmalloc's count of it: a
// commit that would take the count past the limit is a null, out of
// memory, met before the kernel's killer would end the process unnamed.
// No limit is the largest size, so the test is one comparison and no flag
// says whether there is a limit.
struct LimitRange {
  template <typename ParentRange>
  class Type : public snmalloc::ContainsParent<ParentRange> {
    using snmalloc::ContainsParent<ParentRange>::parent;

  public:
    static constexpr bool Aligned = ParentRange::Aligned;
    static constexpr bool ConcurrencySafe = ParentRange::ConcurrencySafe;
    using ChunkBounds = typename ParentRange::ChunkBounds;

    constexpr Type() = default;

    snmalloc::CapPtr<void, ChunkBounds> alloc_range(size_t size) {
      size_t committed = parent.get_current_usage();
      if (committed > limit || limit - committed < size)
        return snmalloc::CapPtr<void, ChunkBounds>(nullptr);
      return parent.alloc_range(size);
    }

    void dealloc_range(snmalloc::CapPtr<void, ChunkBounds> base, size_t size) {
      parent.dealloc_range(base, size);
    }

    static void set(size_t bytes) noexcept { limit = bytes; }

  private:
    SNMALLOC_REQUIRE_CONSTINIT inline static size_t limit = SIZE_MAX;
  };
};

// snmalloc's configuration over the span: its fixed-range shape (a bounded
// page map over the one span, initialised explicitly), its standard ranges
// with the limit after the count of committed memory, and no client
// metadata or domestication, since every pointer the runtime frees is a
// cell of its own heap.
class HeapConfig final : public snmalloc::CommonConfig {
public:
  using Pal = rt::alloc::Pal;
  using ClientMeta = snmalloc::NoClientMetaDataProvider;
  using PagemapEntry = snmalloc::DefaultPagemapEntry<ClientMeta>;
  using SecondaryAllocator = snmalloc::DefaultSecondaryAllocator;

private:
  using ConcretePagemap = snmalloc::FlatPagemap<snmalloc::MIN_CHUNK_BITS, PagemapEntry, Pal, true>;
  using Pagemap = snmalloc::BasicPagemap<Pal, ConcretePagemap, PagemapEntry, true>;

  struct Authmap {
    SNMALLOC_REQUIRE_CONSTINIT inline static snmalloc::capptr::Arena<void> arena{nullptr};

    template <bool potentially_out_of_range = false>
    static SNMALLOC_FAST_PATH snmalloc::capptr::Arena<void>
    amplify(snmalloc::capptr::Alloc<void> c) {
      return snmalloc::Aal::capptr_rebound(arena, c);
    }
  };

  using Base = snmalloc::Pipe<SpanRange, snmalloc::PagemapRegisterRange<Pagemap>>;

public:
  // snmalloc's StandardLocalState, with LimitRange after StatsRange.
  struct LocalState : snmalloc::BaseLocalStateConstants {
    using GlobalR = snmalloc::Pipe<
        Base,
        snmalloc::LargeBuddyRange<GlobalCacheSizeBits, snmalloc::bits::BITS - 1, Pagemap,
                                  snmalloc::MinBaseSizeBits<Pal>()>,
        snmalloc::LogRange<2>, snmalloc::GlobalRange>;
    using Stats = snmalloc::Pipe<GlobalR, snmalloc::CommitRange<Pal>, snmalloc::StatsRange,
                                 LimitRange>;

  private:
    static constexpr size_t pageSizeBits = snmalloc::bits::next_pow2_bits_const(Pal::page_size);

  public:
    using LargeObjectRange = snmalloc::Pipe<
        Stats, snmalloc::StaticConditionalRange<snmalloc::LargeBuddyRange<
                   LocalCacheSizeBits, LocalCacheSizeBits, Pagemap, pageSizeBits>>>;

  private:
    using ObjectRange = snmalloc::Pipe<LargeObjectRange, snmalloc::SmallBuddyRange>;
    ObjectRange objectRange;

  public:
    using GlobalMetaRange = snmalloc::Pipe<ObjectRange, snmalloc::GlobalRange>;

    LargeObjectRange *get_object_range() {
      return objectRange.template ancestor<LargeObjectRange>();
    }
    ObjectRange &get_meta_range() { return objectRange; }
  };

  using Backend = snmalloc::BackendAllocator<Pal, PagemapEntry, Pagemap, Authmap, LocalState>;
  using GlobalPoolState = snmalloc::PoolState<snmalloc::Allocator<HeapConfig>>;

  static constexpr snmalloc::Flags Options{};

  static GlobalPoolState &pool() { return allocators; }

  // The page map's storage at the span's start, a 1/1024 of the span
  // (16 bytes per 16 KiB chunk), reserved inaccessible and committed a page
  // at a time as chunks are registered; the chunks after it.
  static bool init(rt::platform::Span span, size_t limit) noexcept {
    constexpr size_t granule = size_t{1} << snmalloc::MIN_CHUNK_BITS;
    size_t length = span.length & ~(granule - 1);
    size_t mapBytes = rt::platform::roundUp((length >> snmalloc::MIN_CHUNK_BITS) * sizeof(PagemapEntry),
                                            rt::platform::pageSize());
    if (length <= mapBytes ||
        rt::platform::reserveAt(span.base, mapBytes) != rt::platform::Placed::Reserved)
      return false;
    auto [heapBase, heapLength] = Pagemap::concretePagemap.init(span.base, length);
    Authmap::arena = snmalloc::capptr::Arena<void>::unsafe_from(heapBase);
    auto from = reinterpret_cast<uintptr_t>(heapBase);
    SpanRange::set(from, from + heapLength);
    // Stats is LimitRange's own type, the last of its pipe.
    LocalState::Stats::set(limit);
    return true;
  }

private:
  SNMALLOC_REQUIRE_CONSTINIT inline static GlobalPoolState allocators;
};

// The continuation every allocation takes: a block, never a null. What no
// allocation can meet ends the process as out of memory, its output
// written first and nothing allocated on the way down; the language
// promises nothing of which allocation that is.
struct Ends {
  static void *success(void *p, size_t, bool = false) { return p; }
  [[noreturn]] static void *failure(size_t) noexcept { rt::end::end(rt::end::OutOfMemory{}); }
};

} // namespace rt::alloc

namespace snmalloc {
using Config = rt::alloc::HeapConfig;
} // namespace snmalloc

#define SNMALLOC_PROVIDE_OWN_CONFIG
#include <snmalloc/snmalloc.h>

static_assert(snmalloc::DefaultPal::address_bits <= rt::alloc::heapAddressBits,
              "every heap address fits the bits the dying list keeps");
// snmalloc decommits and zeroes by its own page, which must be the target
// entry's (every host of the runtime checks that one against the system's
// first): POSIX platforms take it from SNMALLOC_PAGESIZE, which the build
// sets to it, and Apple's platform has its own constant.
static_assert(snmalloc::OS_PAGE_SIZE == IDRIS_RT_PAGE_SIZE,
              "snmalloc's page is the target entry's page");
static_assert(snmalloc::sizeclass_to_size(snmalloc::size_to_sizeclass_const(24)) == 24,
              "a header and two fields are one size class, with no slack");
static_assert(snmalloc::mitigations(snmalloc::pal_enforce_access),
              "a reservation stays inaccessible until snmalloc commits it");

namespace rt::alloc {

bool initialise(size_t limit) noexcept {
  return HeapConfig::init(rt::platform::heapSpan(size_t{1} << regionBits), limit);
}

char *reserveFirst(size_t size) noexcept {
  return SpanRange::take(size, rt::platform::pageSize());
}

[[gnu::always_inline]] void *allocate(size_t size) { return snmalloc::alloc<Ends>(size); }

size_t classSize(size_t size) { return snmalloc::round_size(size); }

size_t bytesToEnd(const void *inside) { return snmalloc::remaining_bytes(inside); }

// A block whose size class holds the new size stays where it is, which is
// most of what GMP's growing integers ask; any other moves.
void *reallocate(void *block, size_t size) {
  size_t held = snmalloc::alloc_size(block);
  if (snmalloc::round_size(size) == held)
    return block;
  void *moved = allocate(size);
  memcpy(moved, block, held < size ? held : size);
  release(block);
  return moved;
}

void release(void *block) { snmalloc::dealloc(block); }

[[gnu::always_inline]] void *newCell(size_t size, uint32_t info) {
  auto *cell = static_cast<idris_rt_header *>(allocate(size));
  *cell = idris_rt_header{1, info};
  if constexpr (checked) {
    ++cellsHeld;
    ++cellsMade;
  }
  return cell;
}

[[gnu::always_inline]] void freeCell(void *cell) {
  if constexpr (checked) {
    --cellsHeld;
    // Kept, and marked: no later cell takes its memory, so a reference
    // left to it still reads the mark.
    static_cast<idris_rt_header *>(cell)->info = freedInfo;
    return;
  }
  snmalloc::dealloc(cell);
}

} // namespace rt::alloc

// A new cell of `size` bytes, a box or a thunk that idr-lower builds (or,
// with the matching info, anything else the runtime frees): its header is
// count 1 and `info`. Running out of memory is the process's ending. The
// size is a constant at every call idr-lower makes, so once the runtime's
// bitcode is inlined, snmalloc's size class folds to a constant and the
// allocation is a free-list pop.
extern "C" [[gnu::always_inline]] idris_rt_header *idris_rt_cell(int64_t size, int32_t info) {
  return static_cast<idris_rt_header *>(
      rt::alloc::newCell(static_cast<size_t>(size), static_cast<uint32_t>(info)));
}
