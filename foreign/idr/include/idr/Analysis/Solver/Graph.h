// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The graph every solver of ours runs over: nodes are dense ids a minter
// numbered, edges two compressed-row arrays, one per direction. A graph is
// built once by its builder, which is consumed, so a built graph has no
// edit API and every reader of it reads the same rows.
//
// A choice of direction is a type, never a flag: a marking or a walk names
// Forward or Backward, and the graph hands it the rows of that direction.
//
// The forward rows end with one more row, the sentinel root, whose
// successors are every node in id order. LLVM's Tarjan walks from one
// entry; from the root it meets every node, so the components of a graph
// with several entries come out of one walk with no synthetic node copied
// in, and the root's own component, which nothing enters, comes out last.
//
// The rows are 4 bytes per edge and per node in each direction. A graph
// that grows while it is solved (the label solve's) is not one of these:
// it keeps append-only vectors, and freezes into a Csr for each sweep.
#ifndef IDR_ANALYSIS_SOLVER_GRAPH_H
#define IDR_ANALYSIS_SOLVER_GRAPH_H

#include "idr/Support/Id.h"

#include "llvm/ADT/GraphTraits.h"

#include <concepts>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <span>
#include <utility>
#include <vector>

namespace idr {

struct Forward {};
struct Backward {};
template <class D>
concept Direction = std::same_as<D, Forward> || std::same_as<D, Backward>;

// A row of a compressed array, read as typed ids. A range, not a span of
// Id: an Id is not a uint32_t to the aliasing rules, so the row stays raw
// and each element is wrapped as it is read.
template <class IdT>
class IdRange {
public:
  class iterator {
  public:
    using iterator_category = std::random_access_iterator_tag;
    using value_type = IdT;
    using difference_type = std::ptrdiff_t;
    using pointer = void;
    using reference = IdT;

    iterator() = default;
    explicit iterator(const std::uint32_t *at) : at(at) {}
    IdT operator*() const { return IdRange::wrap(*at); }
    IdT operator[](difference_type n) const { return IdRange::wrap(at[n]); }
    iterator &operator++() { ++at; return *this; }
    iterator operator++(int) { iterator was = *this; ++at; return was; }
    iterator &operator--() { --at; return *this; }
    iterator operator--(int) { iterator was = *this; --at; return was; }
    iterator &operator+=(difference_type n) { at += n; return *this; }
    iterator &operator-=(difference_type n) { at -= n; return *this; }
    friend iterator operator+(iterator i, difference_type n) { return i += n; }
    friend iterator operator+(difference_type n, iterator i) { return i += n; }
    friend iterator operator-(iterator i, difference_type n) { return i -= n; }
    friend difference_type operator-(iterator a, iterator b) { return a.at - b.at; }
    friend auto operator<=>(iterator, iterator) = default;

  private:
    const std::uint32_t *at = nullptr;
  };

  IdRange() = default;
  explicit IdRange(std::span<const std::uint32_t> raw) : raw(raw) {}

  iterator begin() const { return iterator(raw.data()); }
  iterator end() const { return iterator(raw.data() + raw.size()); }
  std::size_t size() const { return raw.size(); }
  bool empty() const { return raw.empty(); }
  IdT front() const { return wrap(raw.front()); }
  IdT operator[](std::size_t i) const { return wrap(raw[i]); }

private:
  // An id's minter names IdRange its friend: a row holds ids the minter
  // made, so wrapping one mints nothing.
  static IdT wrap(std::uint32_t at) { return IdT(at); }

  std::span<const std::uint32_t> raw;
};

namespace detail {
// The rows of one direction, with the tag shed: what the loops compiled
// once for every graph read (Mark.cpp, Components.cpp).
struct Rows {
  std::span<const std::uint32_t> start, to;
  std::span<const std::uint32_t> row(std::uint32_t node) const {
    return to.subspan(start[node], start[node + 1] - start[node]);
  }
};

// The counting sort that lays out one direction's rows from an edge list:
// O(nodes + edges), no hash and no comparison sort, each row in the order
// its edges were given. `rows` nodes get a row each; a present `root` appends
// the sentinel root's row of every node.
enum class Root : std::uint8_t { Absent, Present };
void layOut(std::uint32_t rows, std::span<const std::pair<std::uint32_t, std::uint32_t>> edges,
            Root root, std::vector<std::uint32_t> &start, std::vector<std::uint32_t> &to);
} // namespace detail

// A frozen graph over the ids of `Tag`: successors and predecessors as
// rows, and the sentinel root after the last forward row.
template <class Tag>
class Csr {
public:
  using Node = Id<Tag>;

  Count<Node> size() const { return count; }
  IdRange<Node> successors(Node n) const { return IdRange<Node>(rows(Forward{}).row(n.index())); }
  IdRange<Node> predecessors(Node n) const {
    return IdRange<Node>(rows(Backward{}).row(n.index()));
  }
  template <Direction D>
  IdRange<Node> next(Node n, D direction) const {
    return IdRange<Node>(rows(direction).row(n.index()));
  }

  detail::Rows rows(Forward) const { return {succStart, succ}; }
  detail::Rows rows(Backward) const { return {predStart, pred}; }
  // The sentinel root's number: one past the last node.
  std::uint32_t root() const { return count.value(); }

private:
  template <class>
  friend class CsrBuilder;
  explicit Csr(Count<Node> count) : count(count) {}

  Count<Node> count;
  std::vector<std::uint32_t> succStart, predStart, succ, pred;
};

// Edges collected, then laid out. `finish` consumes the builder, so no
// edge can be added to a built graph.
template <class Tag>
class CsrBuilder {
public:
  explicit CsrBuilder(Count<Id<Tag>> n) : count(n) {}

  void edge(Id<Tag> from, Id<Tag> to) { edges.emplace_back(from.index(), to.index()); }

  Csr<Tag> finish() && {
    Csr<Tag> graph(count);
    detail::layOut(count.value(), edges, detail::Root::Present, graph.succStart, graph.succ);
    for (auto &[from, to] : edges)
      std::swap(from, to);
    detail::layOut(count.value(), edges, detail::Root::Absent, graph.predStart, graph.pred);
    return graph;
  }

private:
  Count<Id<Tag>> count;
  std::vector<std::pair<std::uint32_t, std::uint32_t>> edges;
};

template <class G>
concept Graph = requires(const G &g, typename G::Node n) {
  requires std::same_as<typename G::Node, Id<typename G::Node::tag, typename G::Node::rep>>;
  { g.size() } -> std::same_as<Count<typename G::Node>>;
  { g.successors(n) } -> std::same_as<IdRange<typename G::Node>>;
  { g.predecessors(n) } -> std::same_as<IdRange<typename G::Node>>;
};

namespace detail {
// A gated graph's rows with the tag shed: plain edges as rows, guarded
// edges by source, and the same guarded edges by guard.
struct Guarded {
  std::uint32_t to, guard;
};
struct Waiting {
  std::uint32_t from, to;
};
struct GatedRows {
  Rows plain;
  std::span<const std::uint32_t> guardedStart;
  std::span<const Guarded> guarded;
  std::span<const std::uint32_t> waitingStart;
  std::span<const Waiting> waiting;
};
} // namespace detail

// Exclusivity's gates as data, not a callback. An edge either always
// carries the marking, or carries it once its guard node is marked too:
// Horn propagation, linear in nodes and edges, monotone because a guard is
// a node of a set that only rises, so no schedule can change a verdict.
template <class Tag>
class GatedCsr {
public:
  using Node = Id<Tag>;

  Count<Node> size() const { return count; }
  IdRange<Node> plain(Node from) const {
    return IdRange<Node>(detail::Rows{plainStart, plainTo}.row(from.index()));
  }

  detail::GatedRows rows() const {
    return {{plainStart, plainTo}, guardedStart, guardedTo, waitingStart, waitingOn};
  }

private:
  template <class>
  friend class GatedCsrBuilder;
  explicit GatedCsr(Count<Node> count) : count(count) {}

  Count<Node> count;
  std::vector<std::uint32_t> plainStart, plainTo;
  std::vector<std::uint32_t> guardedStart;
  std::vector<detail::Guarded> guardedTo;
  std::vector<std::uint32_t> waitingStart;
  std::vector<detail::Waiting> waitingOn;
};

namespace detail {
// Lays out the guarded edges twice, by source and by guard (Graph.cpp).
void layOutGuarded(std::uint32_t rows, std::span<const std::uint32_t> from,
                   std::span<const Guarded> edges, std::vector<std::uint32_t> &byFromStart,
                   std::vector<Guarded> &byFrom, std::vector<std::uint32_t> &byGuardStart,
                   std::vector<Waiting> &byGuard);
} // namespace detail

template <class Tag>
class GatedCsrBuilder {
public:
  explicit GatedCsrBuilder(Count<Id<Tag>> n) : count(n) {}

  void plain(Id<Tag> from, Id<Tag> to) { plainEdges.emplace_back(from.index(), to.index()); }
  // An edge that carries the marking once `guard` is marked as well.
  void guarded(Id<Tag> from, Id<Tag> to, Id<Tag> guard) {
    guardedFrom.push_back(from.index());
    guardedEdges.push_back({to.index(), guard.index()});
  }

  GatedCsr<Tag> finish() && {
    GatedCsr<Tag> graph(count);
    detail::layOut(count.value(), plainEdges, detail::Root::Absent, graph.plainStart,
                   graph.plainTo);
    detail::layOutGuarded(count.value(), guardedFrom, guardedEdges, graph.guardedStart,
                          graph.guardedTo, graph.waitingStart, graph.waitingOn);
    return graph;
  }

private:
  Count<Id<Tag>> count;
  std::vector<std::pair<std::uint32_t, std::uint32_t>> plainEdges;
  std::vector<std::uint32_t> guardedFrom;
  std::vector<detail::Guarded> guardedEdges;
};

namespace detail {
// One direction of a graph as LLVM's graph algorithms read it, the tag
// shed: a node reference carries its rows, since a number alone reaches no
// row, and its number is what the patched scc_iterator and po_iterator
// index their visit state by.
struct RowGraph {
  Rows rows;
  std::uint32_t root;
};
struct RowNode {
  const RowGraph *graph;
  std::uint32_t node;
  friend bool operator==(RowNode a, RowNode b) { return a.node == b.node; }
};
class RowChildren {
public:
  using iterator_category = std::forward_iterator_tag;
  using value_type = RowNode;
  using difference_type = std::ptrdiff_t;
  using pointer = void;
  using reference = RowNode;

  RowChildren() = default;
  RowChildren(const RowGraph *graph, const std::uint32_t *at) : graph(graph), at(at) {}
  RowNode operator*() const { return {graph, *at}; }
  RowChildren &operator++() { ++at; return *this; }
  RowChildren operator++(int) { RowChildren was = *this; ++at; return was; }
  friend bool operator==(RowChildren a, RowChildren b) { return a.at == b.at; }

private:
  const RowGraph *graph = nullptr;
  const std::uint32_t *at = nullptr;
};
} // namespace detail

} // namespace idr

template <>
struct llvm::GraphTraits<idr::detail::RowNode> {
  using NodeRef = idr::detail::RowNode;
  using ChildIteratorType = idr::detail::RowChildren;
  static NodeRef getEntryNode(NodeRef n) { return n; }
  static ChildIteratorType child_begin(NodeRef n) {
    return {n.graph, n.graph->rows.row(n.node).data()};
  }
  static ChildIteratorType child_end(NodeRef n) {
    std::span<const std::uint32_t> row = n.graph->rows.row(n.node);
    return {n.graph, row.data() + row.size()};
  }
  static unsigned getNumber(NodeRef n) { return n.node; }
};

template <>
struct llvm::GraphTraits<const idr::detail::RowGraph *>
    : llvm::GraphTraits<idr::detail::RowNode> {
  static NodeRef getEntryNode(const idr::detail::RowGraph *g) { return {g, g->root}; }
  static unsigned getMaxNumber(const idr::detail::RowGraph *g) { return g->root + 1; }
  // The rows are frozen: one epoch for the graph's life.
  static unsigned getNumberEpoch(const idr::detail::RowGraph *) { return 0; }
};

#endif // IDR_ANALYSIS_SOLVER_GRAPH_H
