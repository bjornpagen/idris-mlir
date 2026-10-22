// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A union-find over a dense set of keys: each key's parent, a root its own,
// found with its path shortened to the root. It holds the forest alone.
// Which of two roots goes under the other, and what moves with a class,
// are the solve's: the label solve links under the class with the longer
// list of successors, so no long list is copied twice, and the e-graph
// under the class that holds an identity, else the larger, else the older,
// and refuses some unions outright. So a solve chooses, then links.
//
// Nothing here names MLIR, and the forest is the footprint's.
#ifndef IDR_ANALYSIS_SOLVER_UNIONFIND_H
#define IDR_ANALYSIS_SOLVER_UNIONFIND_H

#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "llvm/ADT/STLForwardCompat.h"

#include <cassert>
#include <concepts>
#include <cstddef>
#include <type_traits>

namespace idr::solver {

// A key's place in the forest: its number, whether its set is numbered by
// an Id's minter or as an enum of the solve's own.
template <class Tag, std::unsigned_integral Rep>
constexpr std::size_t slotOf(Id<Tag, Rep> key) {
  return key.index();
}
template <class E>
  requires std::is_enum_v<E> && std::unsigned_integral<std::underlying_type_t<E>>
constexpr std::size_t slotOf(E key) {
  return llvm::to_underlying(key);
}

template <class K>
concept DenseKey = std::equality_comparable<K> && requires(K key) {
  { slotOf(key) } -> std::same_as<std::size_t>;
};

template <DenseKey K>
class UnionFind {
public:
  void reserve(std::size_t keys) { parents.reserve(keys); }

  // `key`, the next its set numbers, a class of its own.
  void add(K key) {
    assert(slotOf(key) == parents.size() && "a key joins the forest in its number's order");
    parents.push_back(key);
  }

  std::size_t size() const { return parents.size(); }

  bool isRoot(K key) const { return parents[slotOf(key)] == key; }

  // The root, each key on the way made its child, so the next find of any
  // of them is one load.
  K find(K key) {
    K root = key;
    while (parents[slotOf(root)] != root)
      root = parents[slotOf(root)];
    while (parents[slotOf(key)] != root) {
      K next = parents[slotOf(key)];
      parents[slotOf(key)] = root;
      key = next;
    }
    return root;
  }

  // The root, read with no path shortened, for a reader that may not write.
  K rootOf(K key) const {
    while (parents[slotOf(key)] != key)
      key = parents[slotOf(key)];
    return key;
  }

  // `child`'s class under `root`'s: two roots, as the solve chose them.
  void link(K child, K root) {
    assert(child != root && isRoot(child) && isRoot(root) && "a union links two roots");
    parents[slotOf(child)] = root;
  }

private:
  footprint::Vector<K> parents;
};

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_UNIONFIND_H
