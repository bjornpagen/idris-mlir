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
// means anything against the partition that minted it. Its tables are the
// footprint's, so a pass's footprint counts every partition it holds.
#ifndef IDR_ANALYSIS_SOLVER_COMPONENTS_H
#define IDR_ANALYSIS_SOLVER_COMPONENTS_H

#include "idr/Analysis/Solver/Graph.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <span>
#include <utility>

namespace idr {

namespace detail {
// The permutation of a graph's nodes, its components' starts (one past the
// last component's end included), and each node's component.
struct RawPartition {
  footprint::Vector<std::uint32_t> order;
  footprint::Vector<std::uint32_t> start;
  footprint::Vector<std::uint32_t> componentOf;
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
  // Whether the component is a cycle: two members or more, or one with an
  // edge to itself.
  bool cyclic(Component c) const { return cycles.test(c); }

private:
  template <class T>
  friend Partition<T> components(const Csr<T> &graph);

  // The partition the walk found, and its cycles read off its runs and the
  // rows it was found in.
  Partition(detail::RawPartition found, detail::Rows forward)
      : raw(std::move(found)), cycles(size()) {
    for (Component c : size().ids()) {
      IdRange<Node> run = members(c);
      std::span<const std::uint32_t> row = forward.row(run.front().index());
      if (run.size() > 1 || std::ranges::find(row, run.front().index()) != row.end())
        (void)cycles.raise(c);
    }
  }
  static std::uint32_t start(std::size_t n) { return static_cast<std::uint32_t>(n); }

  detail::RawPartition raw;
  BitSet<Component> cycles;
};

template <class Tag>
Partition<Tag> components(const Csr<Tag> &graph) {
  detail::Rows forward = graph.rows(Forward{});
  return Partition<Tag>(detail::componentsOf(forward, graph.size().value()), forward);
}

} // namespace idr

#endif // IDR_ANALYSIS_SOLVER_COMPONENTS_H
