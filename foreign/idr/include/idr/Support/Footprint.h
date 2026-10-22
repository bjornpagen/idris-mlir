// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A run's footprint: the most bytes the compiler's state, as the shared
// vocabulary stores it, held on the run's thread beyond what it held when
// the run began. Every table the vocabulary sizes by the program (an
// IndexVector, a BitSet, a Ragged, and any vector a solver keeps its state
// in, a footprint::Vector) takes its memory through one allocator, which
// adds what it takes to the calling thread's ledger and takes off what it
// gives back. A run nested inside another on one thread (a function's
// pipeline inside the module pass that runs it) raises the outer run's
// peak with its own.
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
