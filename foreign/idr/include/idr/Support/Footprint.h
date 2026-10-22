// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A run's footprint: the most bytes the compiler's state, as the shared
// vocabulary stores it, held on the run's thread beyond what it held when
// the run began. Every table the vocabulary sizes by the program (an
// IndexVector, a BitSet, a Ragged, any vector a solver keeps its state in,
// the stack of a walk down a nesting (Nest.h), a footprint::Vector, a
// hashed map or set that must stay hashed, a footprint::DenseMap or
// DenseSet, and an arena things are interned in, a
// footprint::BumpPtrAllocator) takes its memory through this header's
// allocators, which add what they take to the calling thread's ledger and
// take off what they give back. A run nested inside another on one thread
// (a function's pipeline inside the module pass that runs it) raises the
// outer run's peak with its own.
//
// It counts bytes the program's size decides, never a reading of the
// process: the same on every target, at every thread count and on every
// run, so a relation between two sizes of one program reads it as it reads
// a count of work. Storage taken on one thread and given back on another
// lowers the second thread's ledger, so a run never counts what another
// thread holds, and its footprint is never below zero; what a run hands to
// other threads counts on theirs, in the runs they are in.
//
// Nothing here names MLIR; the pass manager's instrumentation that
// measures each pass's runs is Profile.h's.
#ifndef IDR_SUPPORT_FOOTPRINT_H
#define IDR_SUPPORT_FOOTPRINT_H

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/Support/Allocator.h"
#include "llvm/Support/MemAlloc.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <memory>
#include <vector>

namespace idr::footprint {

namespace detail {

// This thread's bytes held now, and the most it has held since its
// innermost measured run began. Constant-initialized, so the allocator
// reaches it with no guard.
struct Ledger {
  std::int64_t held = 0;
  std::int64_t peak = 0;
};

inline constinit thread_local Ledger ledger;

inline void take(std::size_t bytes) noexcept {
  Ledger &here = ledger;
  here.held += static_cast<std::int64_t>(bytes);
  here.peak = std::max(here.peak, here.held);
}

inline void giveBack(std::size_t bytes) noexcept {
  ledger.held -= static_cast<std::int64_t>(bytes);
}

} // namespace detail

// The allocator of the vocabulary's storage: the standard one, each
// allocation counted on the calling thread. It holds nothing, so every
// copy of it is every other, and a container moves its memory with it.
template <class T>
class Allocator {
public:
  using value_type = T;

  constexpr Allocator() noexcept = default;
  template <class U>
  constexpr Allocator(const Allocator<U> &) noexcept {}

  T *allocate(std::size_t n) {
    T *at = std::allocator<T>().allocate(n);
    detail::take(n * sizeof(T));
    return at;
  }

  void deallocate(T *at, std::size_t n) noexcept {
    detail::giveBack(n * sizeof(T));
    std::allocator<T>().deallocate(at, n);
  }
};

template <class T, class U>
constexpr bool operator==(const Allocator<T> &, const Allocator<U> &) noexcept {
  return true;
}

// A vector whose memory counts in the footprint: what a solver keeps state
// sized by the program in.
template <class T>
using Vector = std::vector<T, Allocator<T>>;

// The table of a hashed map whose memory counts in the footprint. A
// DenseMap takes no allocator: its storage is the one place it allocates
// and frees its buckets, so this is LLVM's own storage with each table
// counted at the size LLVM allocates it at, the size getMemorySize reads.
// A map grows by allocating the larger table before it frees the smaller,
// and its peak holds both.
template <class Bucket>
class Buckets : public llvm::densemap::detail::DenseMapStorage<Bucket> {
  using Storage = llvm::densemap::detail::DenseMapStorage<Bucket>;

public:
  bool allocateBuckets(unsigned buckets) {
    bool made = Storage::allocateBuckets(buckets);
    detail::take(bytes());
    return made;
  }

  void deallocateBuckets() {
    detail::giveBack(bytes());
    Storage::deallocateBuckets();
  }

  void grow(unsigned least, llvm::densemap::detail::BucketHasher hasher) {
    std::size_t smaller = bytes();
    Storage::grow(least, hasher);
    detail::take(bytes());
    detail::giveBack(smaller);
  }

private:
  std::size_t bytes() const {
    return llvm::densemap::detail::allocBytes<Bucket>(Storage::getNumBuckets());
  }
};

// A hashed map whose memory counts in the footprint: the map llvm::DenseMap
// is, DenseMapBase, over counted buckets in place of LLVM's storage, which
// is all llvm::DenseMap adds. What a solver keys by content no numbering
// covers.
template <class K, class V, class Info = llvm::DenseMapInfo<K>,
          class Bucket = llvm::detail::DenseMapPair<K, V>>
using DenseMap = llvm::DenseMapBase<Buckets<Bucket>, K, V, Info, Bucket>;

// A hashed set whose memory counts in the footprint: the set llvm::DenseSet
// is, a map to nothing over buckets of keys alone, here the counted map.
template <class K, class Info = llvm::DenseMapInfo<K>>
using DenseSet = llvm::detail::DenseSetImpl<
    K, DenseMap<K, llvm::detail::DenseSetEmpty, Info, llvm::detail::DenseSetPair<K>>>;

// What an arena of LLVM's takes its slabs from, in place of
// llvm::MallocAllocator: the same buffers, each counted on the calling
// thread. An arena takes a slab when its last one is full and moves
// nothing it holds, so its slabs add up until it is reset or ends.
class SlabAllocator {
public:
  void *Allocate(std::size_t bytes, std::size_t alignment) {
    void *at = llvm::allocate_buffer(bytes, alignment);
    detail::take(bytes);
    return at;
  }

  void Deallocate(const void *at, std::size_t bytes, std::size_t alignment) {
    detail::giveBack(bytes);
    llvm::deallocate_buffer(const_cast<void *>(at), bytes, alignment);
  }
};

// An arena whose memory counts in the footprint: what a solver interns
// things of the program's size in.
using BumpPtrAllocator = llvm::BumpPtrAllocatorImpl<SlabAllocator>;

// A run measured on one thread: begun where the run begins, ended where it
// ends, on the same thread, runs nesting as calls do.
class Run {
public:
  // A run beginning now on this thread: its peak starts at what the thread
  // holds.
  static Run begin() noexcept {
    detail::Ledger &here = detail::ledger;
    Run run(here.held, here.peak);
    here.peak = here.held;
    return run;
  }

  // Its footprint, as it ends: the most the thread held beyond what it held
  // when the run began. The run around it, if any, takes this run's peak
  // into its own.
  std::uint64_t end() const noexcept {
    detail::Ledger &here = detail::ledger;
    auto bytes = static_cast<std::uint64_t>(here.peak - start);
    here.peak = std::max(outer, here.peak);
    return bytes;
  }

private:
  Run(std::int64_t start, std::int64_t outer) noexcept : start(start), outer(outer) {}

  // What the thread held when the run began, and the peak of the run around
  // it then.
  std::int64_t start;
  std::int64_t outer;
};

} // namespace idr::footprint

#endif // IDR_SUPPORT_FOOTPRINT_H
