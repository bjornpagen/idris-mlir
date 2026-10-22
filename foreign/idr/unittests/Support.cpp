// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the shared vocabulary (idr/Support): each type against a
// second implementation plain enough to be right by reading, over every
// input of a small domain. Subsets against the bits of an integer, a set
// of ids against the order ids rise in, rows against the function that
// gave them, the fold over a sum against the sum's index, and the walk down
// a nesting against recursion, on every rooted tree of up to six nodes.
// What the vocabulary holds is counted in Footprint.cpp; what a type
// refuses to compile is Refusals.cpp's.

#include "idr/Support/Enum.h"
#include "idr/Support/Id.h"
#include "idr/Support/Match.h"
#include "idr/Support/Nest.h"

#include "llvm/ADT/PointerUnion.h"

#include "gtest/gtest.h"

#include <bit>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <span>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace {

enum class Three : std::uint8_t { A, B, C };
// A closed set of three words, so a subset's words meet at 64 and 128.
enum class Wide : std::uint8_t {};

} // namespace

template <>
struct idr::EnumTraits<Three> {
  static constexpr std::size_t count = 3;
};
template <>
struct idr::EnumTraits<Wide> {
  static constexpr std::size_t count = 130;
};

namespace {

using idr::Changed;
using idr::EnumSet;

// The subset of Three whose members are the bits of `mask`.
EnumSet<Three> subset(unsigned mask) {
  EnumSet<Three> s;
  for (Three e : idr::allOf<Three>())
    if ((mask >> std::to_underlying(e)) & 1)
      (void)s.join({e});
  return s;
}

TEST(EnumSet, EverySubsetAgainstTheBitsOfAnInteger) {
  EXPECT_EQ(EnumSet<Three>::bottom(), subset(0));
  EXPECT_EQ(EnumSet<Three>::top(), subset(7));
  EXPECT_EQ(EnumSet<Three>::height, 3u);
  for (unsigned a = 0; a < 8; ++a) {
    EnumSet<Three> sa = subset(a);
    EXPECT_EQ(sa.empty(), a == 0) << a;
    EXPECT_EQ(sa.size(), static_cast<std::size_t>(std::popcount(a))) << a;
    for (Three e : idr::allOf<Three>())
      EXPECT_EQ(sa.contains(e), ((a >> std::to_underlying(e)) & 1) != 0) << a;
    for (unsigned b = 0; b < 8; ++b) {
      EnumSet<Three> sb = subset(b);
      EXPECT_EQ(sa | sb, subset(a | b)) << a << ", " << b;
      EXPECT_EQ(sa & sb, subset(a & b)) << a << ", " << b;
      EXPECT_EQ(sa - sb, subset(a & ~b & 7u)) << a << ", " << b;
      EXPECT_EQ(sa.includes(sb), (b & ~a) == 0) << a << ", " << b;
      EnumSet<Three> joined = sa;
      Changed grew = joined.join(sb);
      EXPECT_EQ(joined, subset(a | b)) << a << ", " << b;
      EXPECT_EQ(grew, (b & ~a) != 0 ? Changed::Yes : Changed::No) << a << ", " << b;
    }
  }
}

// A case's number, printed as a number.
unsigned number(Wide k) { return std::to_underlying(k); }

TEST(EnumSet, WordsMeetAtTheirEdges) {
  constexpr std::size_t cases = idr::EnumTraits<Wide>::count;
  EXPECT_EQ(EnumSet<Wide>::top().size(), cases);
  EnumSet<Wide> rising;
  for (Wide k : idr::allOf<Wide>()) {
    EnumSet<Wide> one{k};
    EXPECT_EQ(one.size(), 1u) << number(k);
    for (Wide e : idr::allOf<Wide>())
      EXPECT_EQ(one.contains(e), e == k) << number(k);
    EnumSet<Wide> rest = EnumSet<Wide>::top() - one;
    EXPECT_EQ(rest.size(), cases - 1) << number(k);
    EXPECT_FALSE(rest.contains(k)) << number(k);
    EXPECT_EQ(rising.join(one), Changed::Yes) << number(k);
    EXPECT_EQ(rising.join(one), Changed::No) << number(k);
  }
  EXPECT_EQ(rising, EnumSet<Wide>::top());
}

TEST(EnumArray, OneFactPerCaseIndexedByTheCase) {
  idr::EnumArray<Three, int> table{{10, 20, 30}};
  EXPECT_EQ(table[Three::A], 10);
  EXPECT_EQ(table[Three::B], 20);
  EXPECT_EQ(table[Three::C], 30);
  table[Three::B] = 21;
  EXPECT_EQ(table[Three::B], 21);
  EXPECT_EQ(table[Three::C], 30);
}

// Two sets of ids, each numbered here.
struct Things {
  struct Minter;
};
struct Others {
  struct Minter;
};
using Thing = idr::Id<Things>;
using Other = idr::Id<Others>;
struct Things::Minter {
  static idr::Count<Thing> count(std::uint32_t n) { return idr::Count<Thing>(n); }
};
struct Others::Minter {
  static idr::Count<Other> count(std::uint32_t n) { return idr::Count<Other>(n); }
};

TEST(Count, VisitsEveryIdOnceInOrder) {
  std::vector<std::uint32_t> visited;
  for (Thing id : Things::Minter::count(5).ids())
    visited.push_back(id.index());
  EXPECT_EQ(visited, (std::vector<std::uint32_t>{0, 1, 2, 3, 4}));
  EXPECT_TRUE(Things::Minter::count(0).ids().empty());
}

TEST(IndexVector, EachIdHoldsItsOwnFact) {
  idr::Count<Thing> n = Things::Minter::count(7);
  idr::IndexVector<Thing, std::uint32_t> tripled(n, [](Thing id) { return 3 * id.index(); });
  idr::IndexVector<Thing, std::uint32_t> seven(n, 7u);
  idr::IndexVector<Thing, std::uint32_t> zero(n);
  for (Thing id : n.ids()) {
    EXPECT_EQ(tripled[id], 3 * id.index());
    EXPECT_EQ(seven[id], 7u);
    EXPECT_EQ(zero[id], 0u);
  }
  EXPECT_EQ(tripled.size(), n);
  idr::IndexVector<Thing, std::uint32_t> again(n, [](Thing id) { return 3 * id.index(); });
  EXPECT_EQ(tripled, again);
  again[*n.ids().begin()] = 1;
  EXPECT_NE(tripled, again);
  // A fact that is an id of another set, which has no default.
  auto others = Others::Minter::count(7).ids();
  std::vector<Other> each(others.begin(), others.end());
  idr::IndexVector<Thing, Other> mirrored(n, [&](Thing id) { return each[6 - id.index()]; });
  for (Thing id : n.ids())
    EXPECT_EQ(mirrored[id].index(), 6 - id.index());
}

TEST(BitSet, AnIdRisesOnceAndNeverFalls) {
  // Across a word: 70 ids, raised in an order that is not theirs.
  idr::Count<Thing> n = Things::Minter::count(70);
  auto ids = n.ids();
  std::vector<Thing> order(ids.begin(), ids.end());
  for (std::size_t at = 0; at < order.size(); at += 2)
    std::swap(order[at], order[order.size() - 1 - at]);
  idr::BitSet<Thing> marked(n);
  std::vector<bool> raised(70, false);
  for (Thing id : order) {
    EXPECT_FALSE(marked.test(id)) << id.index();
    EXPECT_EQ(marked.raise(id), Changed::Yes) << id.index();
    EXPECT_EQ(marked.raise(id), Changed::No) << id.index();
    raised[id.index()] = true;
    for (Thing other : n.ids())
      EXPECT_EQ(marked.test(other), raised[other.index()]) << id.index();
  }
}

TEST(Ragged, EachOwnerHoldsTheRowItWasGiven) {
  idr::Count<Thing> n = Things::Minter::count(6);
  auto rowOf = [](Thing owner) {
    std::vector<std::uint32_t> row;
    for (std::uint32_t at = 0; at < owner.index(); ++at)
      row.push_back(10 * owner.index() + at);
    return row;
  };
  idr::Ragged<Thing, std::uint32_t> rows(n, rowOf);
  for (Thing owner : n.ids()) {
    std::vector<std::uint32_t> expected = rowOf(owner);
    std::span<const std::uint32_t> got = std::as_const(rows)[owner];
    EXPECT_EQ(std::vector<std::uint32_t>(got.begin(), got.end()), expected) << owner.index();
  }
  // A row written is that row alone.
  Thing third = *std::next(n.ids().begin(), 3);
  rows[third][1] = 0;
  for (Thing owner : n.ids()) {
    std::vector<std::uint32_t> expected = rowOf(owner);
    if (owner == third)
      expected[1] = 0;
    std::span<const std::uint32_t> got = std::as_const(rows)[owner];
    EXPECT_EQ(std::vector<std::uint32_t>(got.begin(), got.end()), expected) << owner.index();
  }
}

using Sum = std::variant<int, std::string, double>;

// The alternative a sum holds, named by its case.
std::string caseOf(const Sum &sum) {
  return idr::match(
      sum, [](int) { return std::string("int"); },
      [](const std::string &) { return std::string("string"); },
      [](double) { return std::string("double"); });
}

TEST(Match, EachAlternativeReachesItsOneCase) {
  const char *names[] = {"int", "string", "double"};
  Sum sums[] = {Sum(std::in_place_index<0>, 1), Sum(std::in_place_index<1>, "one"),
                Sum(std::in_place_index<2>, 1.0)};
  for (const Sum &sum : sums)
    EXPECT_EQ(caseOf(sum), names[sum.index()]);
  // A case of a sum given away may take its alternative.
  Sum text(std::in_place_index<1>, std::string(64, 'x'));
  std::string taken = idr::match(
      std::move(text), [](int &&) { return std::string(); },
      [](std::string &&s) { return std::move(s); }, [](double &&) { return std::string(); });
  EXPECT_EQ(taken, std::string(64, 'x'));
  // A case that gives a reference gives it into the sum.
  Sum number(std::in_place_index<0>, 41);
  int &held = idr::match(
      number, [](int &i) -> int & { return i; },
      [](std::string &) -> int & { static int none = 0; return none; },
      [](double &) -> int & { static int none = 0; return none; });
  ++held;
  EXPECT_EQ(idr::match(
                number, [](int i) { return i; }, [](const std::string &) { return -1; },
                [](double) { return -1; }),
            42);
  // A union of handles, by the same fold.
  int i = 0;
  double d = 0;
  using Handle = llvm::PointerUnion<int *, double *>;
  auto handleCase = [](Handle h) {
    return idr::match(
        h, [](int *) { return 0; }, [](double *) { return 1; });
  };
  EXPECT_EQ(handleCase(Handle(&i)), 0);
  EXPECT_EQ(handleCase(Handle(&d)), 1);
}

// A rooted tree on nodes 0 to n - 1, 0 its root, read from each other
// node's parent: children in increasing order.
using Tree = std::vector<std::vector<unsigned>>;

// The oracle: pre- and post-order by recursion, not entering a node that
// `past` names. The box's trees are at most six deep, so its depth is the
// box's, never an input's.
void walk(const Tree &tree, unsigned node, const std::vector<bool> &past,
          std::vector<unsigned> &pre, std::vector<unsigned> &post) {
  pre.push_back(node);
  if (past[node])
    return;
  for (unsigned child : tree[node])
    walk(tree, child, past, pre, post);
  post.push_back(node);
}

TEST(DepthFirst, EveryTreeInPreAndPostOrder) {
  unsigned trees = 0;
  for (unsigned n = 1; n <= 6; ++n) {
    // Every choice of parent below each node: (n - 1)! trees.
    std::vector<unsigned> parent(n, 0);
    while (true) {
      Tree tree(n);
      for (unsigned node = 1; node < n; ++node)
        tree[parent[node]].push_back(node);
      // Going into every node, then past the nodes of odd number.
      for (unsigned skip = 0; skip < 2; ++skip) {
        std::vector<bool> past(n, false);
        for (unsigned node = 0; node < n; ++node)
          past[node] = skip == 1 && node % 2 == 1;
        std::vector<unsigned> pre, post, entered, left;
        walk(tree, 0, past, pre, post);
        idr::depthFirst(
            0u, [&](const unsigned &node) -> const std::vector<unsigned> & { return tree[node]; },
            [&](const unsigned &node) {
              entered.push_back(node);
              return past[node] ? idr::Descend::Past : idr::Descend::Into;
            },
            [&](const unsigned &node) { left.push_back(node); });
        EXPECT_EQ(entered, pre) << "n " << n << ", skip " << skip;
        EXPECT_EQ(left, post) << "n " << n << ", skip " << skip;
      }
      ++trees;
      // The next parent array, node 1's parent the fastest digit.
      unsigned node = 1;
      while (node < n && parent[node] + 1 == node) {
        parent[node] = 0;
        ++node;
      }
      if (node == n)
        break;
      ++parent[node];
    }
  }
  // 0! + 1! + 2! + 3! + 4! + 5!
  EXPECT_EQ(trees, 154u);
}

} // namespace
