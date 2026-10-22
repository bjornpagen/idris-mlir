// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Strongly connected components, for every graph of ours that must find its
// cycles or be gone through callees first. One walk of LLVM's iterative
// Tarjan from the graph's sentinel root (Graph.h), reading node numbers
// for its visit state, so a chain of any depth takes no recursion and no
// map, and the components come out in an order the graph alone fixes.
//
// The answer is a partition held as ranges of one permutation of the
// nodes: component k's members are a contiguous run, and the runs come
// bottom-up, each after every component it reaches. A component id only
// means anything against the partition that minted it.
#ifndef IDR_ANALYSIS_SOLVER_COMPONENTS_H
#define IDR_ANALYSIS_SOLVER_COMPONENTS_H

#include "idr/Analysis/Solver/Graph.h"
#include "idr/Support/Id.h"

#include "llvm/ADT/BitVector.h"

#include <cstdint>
#include <span>
#include <utility>
#include <vector>

namespace idr {

namespace detail {
// The permutation of a graph's nodes, its components' starts (one past the
// last component's end included), and whether each component is a cycle:
// two members or more, or one with an edge to itself.
struct RawPartition {
  std::vector<std::uint32_t> order;
  std::vector<std::uint32_t> start;
  std::vector<std::uint32_t> componentOf;
  llvm::BitVector cyclic;
};
RawPartition componentsOf(Rows forward, std::uint32_t count);
} // namespace detail

template <class Tag>
class Partition;
template <class Tag>
Partition<Tag> components(const Csr<Tag> &graph);

template <class Tag>
struct ComponentOf {
  using Minter = Partition<Tag>;
};

template <class Tag>
class Partition {
public:
  using Node = Id<Tag>;
  using Component = Id<ComponentOf<Tag>>;

  // Every component, bottom-up: a component's id is below the id of every
  // component that reaches it.
  Count<Component> size() const { return Count<Component>(start(raw.start.size() - 1)); }
  IdRange<Node> members(Component c) const {
    std::span<const std::uint32_t> all = raw.order;
    return IdRange<Node>(all.subspan(raw.start[c.index()],
                                     raw.start[c.index() + 1] - raw.start[c.index()]));
  }
  Component componentOf(Node n) const { return Component(raw.componentOf[n.index()]); }
  bool cyclic(Component c) const { return raw.cyclic.test(c.index()); }

private:
  template <class T>
  friend Partition<T> components(const Csr<T> &graph);

  explicit Partition(detail::RawPartition raw) : raw(std::move(raw)) {}
  static std::uint32_t start(std::size_t n) { return static_cast<std::uint32_t>(n); }

  detail::RawPartition raw;
};

template <class Tag>
Partition<Tag> components(const Csr<Tag> &graph) {
  return Partition<Tag>(detail::componentsOf(graph.rows(Forward{}), graph.size().value()));
}

} // namespace idr

#endif // IDR_ANALYSIS_SOLVER_COMPONENTS_H
