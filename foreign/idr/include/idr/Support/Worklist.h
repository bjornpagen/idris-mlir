// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The two worklists every iteration of ours is, when it is not a loop over a
// finite range. Each carries its termination argument in its type, so a
// solver built on one ends without a count, and a solver that could not end
// cannot be written with one.
//
// OnceWorklist<T>: an element enters at most once ever. The loop ends because
// the elements it can meet are finite.
//
// MonotoneWorklist<T, Lattice>: an element re-enters only when its value in a
// lattice of finite height strictly grew. The loop ends because the elements
// are finite and each grows at most `Lattice::kHeight` times.
//
// A value whose lattice grows with the program, a set over the program's
// labels or functions, has no height a type can state, and a solve over
// (element, member) pairs holds and visits elements times members, however
// few distinct sets there are. Such a solve interns its sets, so an element
// holds a set's identity and a set exists once, and goes in sweeps over its
// graph with each cycle collapsed: one sweep is a loop over a finite DAG,
// and a sweep after the first exists only because an event of a finite set
// happened for the first time in the one before (the label solve's
// firings, Analysis/Labels.cpp).
//
// Both hand elements out first in, first out: an element queued early is not
// starved by the work it causes, so a monotone solve re-enters less.
#ifndef IDR_SUPPORT_WORKLIST_H
#define IDR_SUPPORT_WORKLIST_H

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseMapInfo.h"
#include "llvm/ADT/SetVector.h"

#include <cassert>
#include <concepts>
#include <cstddef>
#include <deque>
#include <optional>
#include <type_traits>

namespace idr {

// An element a worklist can remember: a key of LLVM's hashed containers.
template <typename T>
concept WorklistElement =
    std::copy_constructible<T> && requires(const T &a, const T &b) {
      { llvm::DenseMapInfo<T>::getHashValue(a) } -> std::convertible_to<unsigned>;
      { llvm::DenseMapInfo<T>::isEqual(a, b) } -> std::same_as<bool>;
    };

// A join-semilattice of finite height. The default value is bottom. `join`
// raises the value to the least upper bound of it and its argument, and says
// whether it changed, that is whether it strictly grew. `kHeight` is the
// number of strict steps in the longest chain from bottom: no value grows more
// often than that.
template <typename L>
concept FiniteLattice =
    std::default_initializable<L> && std::copy_constructible<L> &&
    requires(L &value, const L &other) {
      { value.join(other) } -> std::same_as<bool>;
      typename std::integral_constant<std::size_t, L::kHeight>;
    };

// A worklist into which an element enters at most once ever.
template <WorklistElement T>
class OnceWorklist {
public:
  OnceWorklist() = default;

  // Queues `element` unless it has entered before; whether it entered now.
  bool push(const T &element) { return order.insert(element); }

  // The next element in order of entry, or none when every element that
  // entered has been handed out.
  std::optional<T> pop() {
    if (next == order.size())
      return std::nullopt;
    return order[next++];
  }

  // Whether `element` ever entered, handed out or not.
  bool contains(const T &element) const { return order.contains(element); }

  // Every element that entered, in order of entry.
  llvm::ArrayRef<T> entered() const { return order.getArrayRef(); }

private:
  // Every element that entered, in order; those before `next` were handed
  // out. Nothing leaves, so `next` only moves forward over a sequence that
  // grows by distinct elements alone.
  llvm::SetVector<T> order;
  std::size_t next = 0;
};

// A worklist into which an element re-enters only when its value strictly
// grew in `Lattice`.
template <WorklistElement T, FiniteLattice Lattice>
class MonotoneWorklist {
public:
  MonotoneWorklist() = default;

  // Joins `value` into `element`'s value, queueing the element if it is new
  // or its value grew and it is not already queued; whether it is new or
  // grew. A new element enters even with bottom, so seeding an element runs
  // it once.
  bool push(const T &element, const Lattice &value) {
    auto [at, fresh] = entries.try_emplace(element);
    Entry &entry = at->second;
    bool grew = entry.value.join(value);
    if (!fresh && !grew)
      return false;
    if (!entry.queued) {
      entry.queued = true;
      ++entry.entries;
      assert(entry.entries <= Lattice::kHeight + 1 &&
             "an element grew more often than its lattice's kHeight allows");
      queue.push_back(element);
    }
    return true;
  }

  // The next queued element, or none when no element is queued. Its value is
  // `value(element)`, which may have grown since it was queued.
  std::optional<T> pop() {
    if (queue.empty())
      return std::nullopt;
    T element = queue.front();
    queue.pop_front();
    entries.find(element)->second.queued = false;
    return element;
  }

  // The value joined into `element` so far; bottom for one never pushed. The
  // reference lasts until the next push.
  const Lattice &value(const T &element) const {
    static const Lattice bottom{};
    auto at = entries.find(element);
    return at == entries.end() ? bottom : at->second.value;
  }

private:
  struct Entry {
    Lattice value{};
    bool queued = false;
    // Kept in every build, so that the layout does not depend on assertions;
    // only assertion builds check it.
    std::size_t entries = 0;
  };

  llvm::DenseMap<T, Entry> entries;
  std::deque<T> queue;
};

} // namespace idr

#endif // IDR_SUPPORT_WORKLIST_H
