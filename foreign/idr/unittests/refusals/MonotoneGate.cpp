// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A gate of exclusivity's marking is data, a guard node of a set that only
// rises, never a callback: a callback could close a gate once its guard is
// marked, and the verdict would then change with the order nodes rise, so
// with the thread count. The marking takes no gate callback at all.

#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/Mark.h"
#include "idr/Support/Id.h"

#include <span>

struct Nodes {
  struct Minter;
};
using Node = idr::Id<Nodes>;
struct Nodes::Minter {};

idr::BitSet<Node> marked(const idr::GatedCsr<Nodes> &graph, std::span<const Node> seeds) {
  return idr::mark(graph, seeds);
}

idr::BitSet<Node> gatedByCallback(const idr::GatedCsr<Nodes> &graph,
                                  std::span<const Node> seeds) {
  auto closesOnceGuarded = [](Node, Node, const idr::BitSet<Node> &rose, Node guard) {
    return !rose.test(guard);
  };
  return idr::mark(graph, seeds, closesOnceGuarded); // expected-error {{no matching function for call to 'mark'}}
}
