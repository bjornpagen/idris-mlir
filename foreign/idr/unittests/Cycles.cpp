// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of strongly connected components (idr::components), which every
// graph of ours that must find its cycles or be gone through callees first
// reads, the program's calls among them: every directed graph on up to
// four nodes, self edges included, against reachability. Two nodes are in
// one component exactly when each reaches the other; a component is a
// cycle exactly when its nodes reach themselves; every component comes
// after the components it reaches; and the members of the components are
// every node once. The judgement is shown failing each oracle planted with
// a fault.

#include "idr/Analysis/Solver/Components.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Support/Id.h"

#include "gtest/gtest.h"

#include <array>
#include <cstdint>
#include <string>
#include <utility>

namespace {

constexpr unsigned most = 4;
using Matrix = std::array<std::array<bool, most>, most>;

// The nodes of one case's graph, numbered here.
struct Nodes {
  struct Minter;
};
using Node = idr::Id<Nodes>;
struct Nodes::Minter {
  static idr::Count<Node> count(unsigned n) { return idr::Count<Node>(n); }
};

// A graph on `n` nodes read from bits: bit i * n + j is an edge from i to j.
Matrix edgesOf(unsigned n, std::uint32_t bits) {
  Matrix edges{};
  for (unsigned i = 0; i < n; ++i)
    for (unsigned j = 0; j < n; ++j)
      edges[i][j] = ((bits >> (i * n + j)) & 1) != 0;
  return edges;
}

// Reachability through one edge or more (Floyd-Warshall's closure).
Matrix reaches(unsigned n, const Matrix &edges) {
  Matrix r = edges;
  for (unsigned k = 0; k < n; ++k)
    for (unsigned i = 0; i < n; ++i)
      for (unsigned j = 0; j < n; ++j)
        r[i][j] = r[i][j] || (r[i][k] && r[k][j]);
  return r;
}

// What a judge takes for the truth: reachability. The box's is the
// closure; a mutant's is wrong, and the judge must say so.
using Oracle = Matrix (*)(unsigned, const Matrix &);

std::string describe(unsigned n, std::uint32_t bits) {
  return "graph " + std::to_string(bits) + " on " + std::to_string(n) + " nodes";
}

// Whether a failing case is reported: by the box's own judgement, each;
// by a mutant's, none, since a mutant must fail.
enum class Report : std::uint8_t { Each, None };

// The cases whose components disagree with `oracle`, over every graph on
// one to four nodes, up to `limit`; each reported as a failure when
// `report` says so.
template <Oracle oracle>
unsigned judge(unsigned limit, Report report) {
  unsigned failures = 0;
  for (unsigned n = 1; n <= most; ++n) {
    idr::Count<Node> count = Nodes::Minter::count(n);
    for (std::uint32_t bits = 0; bits < (std::uint32_t{1} << (n * n)) && failures < limit;
         ++bits) {
      Matrix edges = edgesOf(n, bits);
      Matrix r = oracle(n, edges);
      idr::CsrBuilder<Nodes> builder(count);
      for (Node from : count.ids())
        for (Node to : count.ids())
          if (edges[from.index()][to.index()])
            builder.edge(from, to);
      idr::Csr<Nodes> graph = std::move(builder).finish();
      idr::Partition<Nodes> parts = idr::components(graph);
      auto fail = [&](const std::string &what) {
        ++failures;
        if (report == Report::Each)
          ADD_FAILURE() << what << " in " << describe(n, bits);
      };
      for (Node i : count.ids()) {
        auto ci = parts.componentOf(i);
        if (parts.cyclic(ci) != r[i.index()][i.index()])
          fail("cyclic(" + std::to_string(i.index()) + ")");
        for (Node j : count.ids()) {
          bool together = i == j || (r[i.index()][j.index()] && r[j.index()][i.index()]);
          auto cj = parts.componentOf(j);
          if ((ci == cj) != together)
            fail("together(" + std::to_string(i.index()) + ", " + std::to_string(j.index()) + ")");
          if (edges[i.index()][j.index()] && !together && !(cj < ci))
            fail(std::to_string(j.index()) + "'s component is not before " +
                 std::to_string(i.index()) + "'s");
        }
      }
      // Every node is a member of its own component, and of no other.
      std::array<unsigned, most> seen{};
      for (auto c : parts.size().ids())
        for (Node member : parts.members(c)) {
          ++seen[member.index()];
          if (parts.componentOf(member) != c)
            fail("member " + std::to_string(member.index()) + " of another component");
        }
      for (Node i : count.ids())
        if (seen[i.index()] != 1)
          fail("node " + std::to_string(i.index()) + " a member " +
               std::to_string(seen[i.index()]) + " times");
    }
  }
  return failures;
}

TEST(Components, EveryGraphAgainstReachability) {
  EXPECT_EQ(judge<reaches>(10, Report::Each), 0u);
}

// One edge, not a path of them: a cycle through three nodes is then no
// cycle, and a node with no self edge is never on one.
Matrix oneEdge(unsigned, const Matrix &edges) { return edges; }

// A self edge taken for no cycle.
Matrix noSelfEdges(unsigned n, const Matrix &edges) {
  Matrix withoutSelf = edges;
  for (unsigned i = 0; i < n; ++i)
    withoutSelf[i][i] = false;
  Matrix r = reaches(n, withoutSelf);
  return r;
}

// The judgement can fail: each oracle with a planted fault disagrees with
// the components on some graph of the box.
TEST(Components, EachMutantOracleIsCaught) {
  EXPECT_GT(judge<oneEdge>(1, Report::None), 0u);
  EXPECT_GT(judge<noSelfEdges>(1, Report::None), 0u);
}

} // namespace
