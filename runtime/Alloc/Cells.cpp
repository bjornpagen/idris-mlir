// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime's memory over snmalloc: raw blocks, and cells, which it
// counts while they live. snmalloc is included here alone, so its fast
// paths inline into newCell and freeCell in every build. Those two, the
// allocation under them and idris_rt_cell are always inlined wherever the
// runtime's bitcode is joined, every program among them: idr-lower calls
// idris_rt_cell with a constant size, so the size class folds and an
// allocation is a thread-local free-list pop in the caller, whatever the
// inliner's budget says. A unit compiled alone calls them.
//
// snmalloc is configured at compile time only (runtime/CMakeLists.txt): size
// classes step by 8 bytes, so a cell of an 8-byte header and two fields
// takes exactly 24; no thread teardown that needs a static destructor or the
// C++ runtime; and its own small STL instead of the C++ library's. Its
// global configuration is HeapConfig below, which places the heap.
// PIN(runtime-quarantine) — see PINS.md
#include "Alloc/Alloc.h"
#include "Platform/Address.h"
#include "Platform/Platform.h"
#include "idris_rt.h"

#include <stddef.h>
#include <stdint.h>

#include <snmalloc/backend/globalconfig.h>
#include <snmalloc/snmalloc_core.h>

namespace rt::alloc {

// The heap starts in one region of 4 GiB, aligned to 4 GiB, so every cell of
// a heap smaller than that has the same upper 32 bits as every other. That is
// what a data memory-dependent prefetcher asks of a word before it follows
// it (Apple's, which scans each cache line a load fills and fetches what a
// word in it points to, only when the word and its address share their 4 GiB
// region). A heap that outgrows the region grows from snmalloc's platform
// layer, as it would without one. The region is address space alone, which
// costs nothing on a target with no such prefetcher.
constexpr size_t heapRegion = size_t{1} << 32;

// snmalloc's standard configuration (StandardConfigClientMeta in
// snmalloc/backend/globalconfig.h, with no client metadata and without the
// metadata protection no mitigation of ours enables), with one addition: its
// initialisation, on the first allocation, gives the global range the heap's
// region before anything is drawn from it, as snmalloc's fixed-range
// configuration gives it its one range.
class HeapConfig final : public snmalloc::CommonConfig {
  using GlobalPoolState = snmalloc::PoolState<snmalloc::Allocator<HeapConfig>>;

public:
  using Pal = snmalloc::DefaultPal;
  using ClientMeta = snmalloc::NoClientMetaDataProvider;
  using PagemapEntry = snmalloc::DefaultPagemapEntry<ClientMeta>;
  using SecondaryAllocator = snmalloc::DefaultSecondaryAllocator;

private:
  using ConcretePagemap =
      snmalloc::FlatPagemap<snmalloc::MIN_CHUNK_BITS, PagemapEntry, Pal, false>;
  using Pagemap = snmalloc::BasicPagemap<Pal, ConcretePagemap, PagemapEntry, false>;
  using ConcreteAuthmap = snmalloc::FlatPagemap<snmalloc::MinBaseSizeBits<Pal>(),
                                                snmalloc::capptr::Arena<void>, Pal, false>;
  using Authmap = snmalloc::DefaultAuthmap<ConcreteAuthmap>;
  using Base = snmalloc::Pipe<snmalloc::PalRange<Pal>, snmalloc::PagemapRegisterRange<Pagemap>,
                              snmalloc::PagemapRegisterRange<Authmap>>;
  static_assert(!snmalloc::mitigations(snmalloc::metadata_protection),
                "the standard local state, not the metadata-protecting one");

public:
  using LocalState = snmalloc::StandardLocalState<Pal, Pagemap, Base>;
  using Backend = snmalloc::BackendAllocator<Pal, PagemapEntry, Pagemap, Authmap, LocalState>;

  static constexpr snmalloc::Flags Options{};

  static GlobalPoolState &pool() { return allocators; }

  static bool is_initialised() { return initialised; }

  SNMALLOC_FAST_PATH static void ensure_init() {
    if (initialised.load(snmalloc::stl::memory_order_acquire)) [[likely]]
      return;
    initialise();
  }

private:
  SNMALLOC_REQUIRE_CONSTINIT inline static GlobalPoolState allocators;
  SNMALLOC_REQUIRE_CONSTINIT inline static snmalloc::stl::Atomic<bool> initialised{false};
  SNMALLOC_REQUIRE_CONSTINIT inline static snmalloc::FlagWord initialising{};

  // The region enters the global range as a block from the platform layer
  // would, registered first: the range keeps its free blocks in their
  // pagemap entries. A system that grants no such region leaves the range
  // empty, and the heap grows from the platform layer alone.
  static void addRegion() {
    char *region = rt::platform::reserve(heapRegion, heapRegion);
    if (region == nullptr)
      return;
    auto arena = snmalloc::capptr::Arena<void>::unsafe_from(region);
    if (!Pagemap::register_range(arena, heapRegion) ||
        !Authmap::register_range(arena, heapRegion)) {
      rt::platform::release(region, heapRegion);
      return;
    }
    LocalState::GlobalR global;
    global.dealloc_range(arena, heapRegion);
  }

  SNMALLOC_SLOW_PATH static void initialise() {
    snmalloc::with(initialising, [] {
      if (initialised)
        return;
      SecondaryAllocator::initialize();
      snmalloc::LocalEntropy entropy;
      entropy.init<Pal>();
      entropy.make_free_list_key(snmalloc::RemoteAllocator::key_global);
      entropy.make_free_list_key(snmalloc::freelist::Object::key_root);
      static constexpr bool randomPagemap = snmalloc::mitigations(snmalloc::random_pagemap) &&
                                            !snmalloc::aal_supports<snmalloc::StrictProvenance>;
      Pagemap::concretePagemap.init<randomPagemap>();
      if constexpr (snmalloc::aal_supports<snmalloc::StrictProvenance>)
        Authmap::init();
      addRegion();
      initialised.store(true, snmalloc::stl::memory_order_release);
    });
  }
};

} // namespace rt::alloc

namespace snmalloc {
using Config = rt::alloc::HeapConfig;
} // namespace snmalloc

#define SNMALLOC_PROVIDE_OWN_CONFIG
#include <snmalloc/snmalloc.h>

static_assert(snmalloc::DefaultPal::address_bits <= rt::alloc::heapAddressBits,
              "every heap address fits the bits the dying list keeps");
// The target's user space lies within what snmalloc's platform layer
// addresses, so a stack address is bounded as a heap address is.
static_assert(rt::platform::userAddressBits <= snmalloc::DefaultPal::address_bits,
              "snmalloc's platform covers the target's user address space");
// snmalloc decommits and zeroes by its own page, which must be the target
// entry's (rt::platform checks that one against the system's at startup):
// POSIX platforms take it from SNMALLOC_PAGESIZE, which the build sets to
// it, and Apple's platform has its own constant.
static_assert(snmalloc::OS_PAGE_SIZE == IDRIS_RT_PAGE_SIZE,
              "snmalloc's page is the target entry's page");
static_assert(snmalloc::sizeclass_to_size(snmalloc::size_to_sizeclass_const(24)) == 24,
              "a header and two fields are one size class, with no slack");

namespace {

// The calling thread's live cells. Per thread, so that counting stays plain
// arithmetic without a data race: a program has one thread, and the
// compiler's folders, which may run on several, read it around each fold,
// on their own thread.
thread_local uint64_t liveCells = 0;

} // namespace

namespace rt::alloc {

void outOfMemory() {
  static constexpr char cause[] = "out of memory";
  idris_rt_crash(cause, sizeof cause - 1);
}

[[gnu::always_inline]] void *allocate(size_t size) {
  void *block = snmalloc::alloc(size);
  if (block == nullptr) [[unlikely]]
    outOfMemory();
  return block;
}

// snmalloc keeps the block when the new size is in its size class, which
// is most of what GMP's growing integers ask. GMP never asks for 0 bytes,
// the one size for which realloc frees and gives null.
void *reallocate(void *block, size_t size) {
  void *moved = snmalloc::libc::realloc(block, size);
  if (moved == nullptr) [[unlikely]]
    outOfMemory();
  return moved;
}

void release(void *block) { snmalloc::dealloc(block); }

[[gnu::always_inline]] void *newCell(size_t size, uint32_t info) {
  auto *cell = static_cast<idris_rt_header *>(allocate(size));
  *cell = idris_rt_header{1, info};
  ++liveCells;
  return cell;
}

[[gnu::always_inline]] void freeCell(void *cell) {
  --liveCells;
  snmalloc::dealloc(cell);
}

} // namespace rt::alloc

// A new cell of `size` bytes, a box or a thunk that idr-lower builds (or,
// with the matching info, anything else the runtime frees): its header is
// count 1 and `info`, and it counts as a live cell. Exhausted memory ends
// the process with a crash. The size is a constant at every call idr-lower
// makes, so once the runtime's bitcode is inlined, snmalloc's size class
// folds to a constant and the allocation is a free-list pop.
extern "C" [[gnu::always_inline]] void *idris_rt_cell(size_t size, uint32_t info) {
  return rt::alloc::newCell(size, info);
}

// The heap cells the runtime allocated (idris_rt_cell, strings and bignums)
// and has not freed yet, counted by the calling thread: a program is
// single-threaded, and idris-mlir reads it before and after each fold, on
// the thread that folds, with no atomic operation on the allocation path.
extern "C" uint64_t idris_rt_live_cells(void) { return liveCells; }
