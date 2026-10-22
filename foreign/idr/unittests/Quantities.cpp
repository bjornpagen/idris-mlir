// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the reuse token's handle (idr/IR/Quantities.h), by which
// counting's walk holds each dead cell once. Each case is an op that runs
// exactly one of its regions, built from a seed: up to three tokens held
// before it, each branched into every region; each region keeps some of
// them and frees the rest at its head, holds tokens born in it, and either
// rejoins the op at its results or leaves it another way, freeing what it
// holds; then the regions that rejoin meet, the code after the op wanting
// a few of each size. Every handle given out is consumed exactly once, to
// its own token: a branch gives one handle per region, each the token
// branched. Of each size, as many join as the fewest any rejoining region
// holds and the code after wants, the k-th taking each region's k-th token
// of it, in region order; every other token is dropped by its own region;
// and the sizes the rejoin gives back are its joins', in the order it made
// them. The judgement is shown failing each model planted with a fault.
// What the handle refuses to compile is Refusals.cpp's.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Quantities.h"
#include "idr/Support/Enum.h"
#include "idr/Testing/Draws.h"

#include "mlir/AsmParser/AsmParser.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include "gtest/gtest.h"

#include <algorithm>
#include <compare>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace {

// The sizes a case's tokens are of: the layouts the rejoin is over.
enum class Size : std::uint8_t { Small, Middle, Large };
// What a region does with a token held before the op: keeps it, or frees
// it at its head.
enum class Keep : std::uint8_t { Kept, Freed };
// How a region ends: rejoining the op at its results, or leaving it another
// way (a return, a jump), which frees what it holds.
enum class End : std::uint8_t { Rejoins, Leaves };

} // namespace

template <>
struct idr::EnumTraits<Size> {
  static constexpr std::size_t count = 3;
};
template <>
struct idr::EnumTraits<Keep> {
  static constexpr std::size_t count = 2;
};
template <>
struct idr::EnumTraits<End> {
  static constexpr std::size_t count = 2;
};

namespace {

using idr::EnumArray;
using idr::box::Draws;

constexpr EnumArray<Size, const char *> sizeNames{{"small", "middle", "large"}};

// The number of seeds the box builds a case from; the most tokens held
// before the op, regions, tokens born in one region, and of one size the
// code after the op wants.
constexpr std::uint64_t seeds = 4000;
constexpr unsigned mostBefore = 3;
constexpr unsigned mostRegions = 4;
constexpr unsigned mostBorn = 3;
constexpr unsigned mostWanted = 3;
// Every token a case can name.
constexpr unsigned mostTokens = mostBefore + mostRegions * mostBorn;

// A token of a case: the value it is, by its number, and its size.
struct Named {
  unsigned token;
  Size size;
};

// A region of a case: the tokens it holds at its end, in the order it
// holds them, those kept from before the op among those born in it; the
// tokens from before the op it frees at its head; and how it ends.
struct Region {
  std::vector<Named> holds;
  std::vector<unsigned> freed;
  End end;
};

// A case: the tokens held before the op, numbered from 0; its regions,
// born tokens numbered after; how many of each size the code after wants.
struct Case {
  std::vector<Named> before;
  std::vector<Region> regions;
  EnumArray<Size, std::uint32_t> wanted;
};

// How often each choice comes in one case, drawn first from its seed, the
// first case of each choice at least once in four.
struct Swarm {
  EnumArray<Size, unsigned> size;
  EnumArray<Keep, unsigned> keep;
  EnumArray<End, unsigned> end;

  explicit Swarm(Draws &draws)
      : size{{1 + draws.below(4), draws.below(5), draws.below(5)}},
        keep{{1 + draws.below(4), draws.below(5)}}, end{{1 + draws.below(4), draws.below(4)}} {}
};

Case caseOf(std::uint64_t seed) {
  Draws draws(seed);
  Swarm swarm(draws);
  Case c{{}, {}, {}};
  unsigned next = 0;
  for (unsigned n = draws.below(mostBefore + 1); n > 0; --n)
    c.before.push_back({next++, draws.weighted(swarm.size)});
  for (unsigned r = draws.below(mostRegions + 1); r > 0; --r) {
    Region region{{}, {}, draws.weighted(swarm.end)};
    for (const Named &held : c.before) {
      if (draws.weighted(swarm.keep) == Keep::Kept)
        region.holds.push_back(held);
      else
        region.freed.push_back(held.token);
    }
    // Each token born in the region anywhere among what it holds, so the
    // first of a size is one from before the op in one region and one
    // born there in another.
    for (unsigned n = draws.below(mostBorn + 1); n > 0; --n) {
      auto at = region.holds.begin() +
                static_cast<std::ptrdiff_t>(draws.below(region.holds.size() + 1));
      region.holds.insert(at, Named{next++, draws.weighted(swarm.size)});
    }
    c.regions.push_back(std::move(region));
  }
  for (Size s : idr::allOf<Size>())
    c.wanted[s] = draws.below(mostWanted + 1);
  return c;
}

std::string describe(const Case &c) {
  auto named = [](const Named &n) {
    return " t" + std::to_string(n.token) + ":" + sizeNames[n.size];
  };
  std::string text = "\n  before:";
  for (const Named &n : c.before)
    text += named(n);
  for (unsigned r = 0; r < c.regions.size(); ++r) {
    const Region &region = c.regions[r];
    text += "\n  region " + std::to_string(r) +
            (region.end == End::Rejoins ? " rejoins, holding" : " leaves, holding");
    for (const Named &n : region.holds)
      text += named(n);
    if (!region.freed.empty())
      text += ", freeing";
    for (unsigned token : region.freed)
      text += " t" + std::to_string(token);
  }
  text += "\n  wanted:";
  for (Size s : idr::allOf<Size>())
    text += " " + std::string(sizeNames[s]) + " " + std::to_string(c.wanted[s]);
  return text;
}

// A join: its size, and its tokens, one per rejoining region in region
// order.
struct Joined {
  Size size;
  std::vector<unsigned> tokens;

  bool operator==(const Joined &) const = default;
};

std::string describe(const std::vector<Joined> &joins) {
  std::string text = "[";
  for (const Joined &j : joins) {
    text += " (";
    for (unsigned token : j.tokens)
      text += " t" + std::to_string(token);
    text += " )";
  }
  return text + " ]";
}

// A drop: the rejoining region by its position among those that rejoin,
// the size, and the token.
struct Dropped {
  unsigned arm;
  Size size;
  unsigned token;

  auto operator<=>(const Dropped &) const = default;
};

// The fault a model of the handle is planted with, if any.
enum class Plant : std::uint8_t {
  None,
  AlwaysAPath,
  Uncapped,
  FirstRegionOnly,
  LastFirst,
  NothingJoinsAll,
  DropsShifted
};

// What a judge takes for the truth of a case: how many handles a branch
// into its regions gives, each size's joins in order, and every drop,
// sorted. A mutant's is wrong in one way, and the judge must say so: an op
// that enters no region given a handle anyway; joins not capped by what
// the code after wants; capped by the first rejoining region alone; taking
// each region's last tokens of a size first; with no region rejoining,
// joins from nothing; a drop named by the next region.
struct Model {
  unsigned handles;
  EnumArray<Size, std::vector<Joined>> joins;
  std::vector<Dropped> drops;
};

template <Plant P>
Model modelOf(const Case &c) {
  auto paths = static_cast<unsigned>(c.regions.size());
  Model model{P == Plant::AlwaysAPath ? std::max(paths, 1u) : paths, {}, {}};
  std::vector<const Region *> arms;
  for (const Region &region : c.regions)
    if (region.end == End::Rejoins)
      arms.push_back(&region);
  auto arity = static_cast<unsigned>(arms.size());
  for (Size s : idr::allOf<Size>()) {
    // Each rejoining region's tokens of the size, in its order.
    std::vector<std::vector<unsigned>> of;
    for (const Region *arm : arms) {
      std::vector<unsigned> tokens;
      for (const Named &held : arm->holds)
        if (held.size == s)
          tokens.push_back(held.token);
      of.push_back(std::move(tokens));
    }
    std::size_t n = P == Plant::Uncapped ? std::numeric_limits<std::size_t>::max() : c.wanted[s];
    if (arms.empty())
      n = P == Plant::NothingJoinsAll ? c.wanted[s] : 0;
    for (unsigned a = 0; a < (P == Plant::FirstRegionOnly ? std::min(arity, 1u) : arity); ++a)
      n = std::min(n, of[a].size());
    for (std::size_t k = 0; k < n; ++k) {
      Joined j{s, {}};
      for (const std::vector<unsigned> &tokens : of)
        if (k < tokens.size())
          j.tokens.push_back(P == Plant::LastFirst ? tokens[tokens.size() - 1 - k] : tokens[k]);
      model.joins[s].push_back(std::move(j));
    }
    for (unsigned a = 0; a < arity; ++a)
      for (std::size_t at = 0; at < of[a].size(); ++at) {
        std::size_t rank = P == Plant::LastFirst ? of[a].size() - 1 - at : at;
        if (rank < n)
          continue;
        unsigned arm = P == Plant::DropsShifted ? (a + 1) % arity : a;
        model.drops.push_back({arm, s, of[a][at]});
      }
  }
  std::ranges::sort(model.drops);
  return model;
}

// Whether a failing case is reported: by the box's own judgement, each;
// by a mutant's, none, since a mutant must fail.
enum class Report : std::uint8_t { Each, None };

// The type of every case's tokens, in the dialect's own text: a token used
// once and unshared, of a list's cons cell. The handle never reads it; the
// tokens are real so that the box holds what counting holds.
constexpr const char *tokenText =
    "!idr.graded<once, counted unique deep, !idr.token<{!idr.data<"
    "#idr.family<\"List\" [] { @Nil () @Cons (i64, !idr.self) }> @Cons>}>>";

// The cases, over every seed up to `limit` of them, where what the handle
// does disagrees with `P`'s model, or a handle given out is not consumed
// exactly once, to its own token.
template <Plant P>
unsigned judge(unsigned limit, Report report) {
  mlir::MLIRContext context;
  context.disableMultithreading();
  context.loadDialect<idr::IdrDialect>();
  mlir::Type tokenType = mlir::parseType(tokenText, &context);
  if (!tokenType) {
    ADD_FAILURE() << "the box's token type does not parse: " << tokenText;
    return limit;
  }
  // The tokens, each a value of its own, and the number of each; a value
  // that is none of them, as the empty value of a handle already consumed
  // is, numbers past the last.
  mlir::Block pool;
  std::vector<mlir::Value> values;
  for (unsigned t = 0; t < mostTokens; ++t)
    values.push_back(pool.addArgument(tokenType, mlir::UnknownLoc::get(&context)));
  auto numberOf = [&](mlir::Value value) {
    return static_cast<unsigned>(llvm::find(values, value) - values.begin());
  };
  unsigned failures = 0;
  for (std::uint64_t seed = 1; seed <= seeds && failures < limit; ++seed) {
    Case c = caseOf(seed);
    Model model = modelOf<P>(c);
    std::string why;
    auto fail = [&](const std::string &what) { why += "\n  " + what; };
    auto paths = static_cast<unsigned>(c.regions.size());
    // Each region's handle on each token held before the op.
    llvm::SmallVector<llvm::SmallVector<idr::Token>> branched;
    for (const Named &held : c.before) {
      branched.push_back(idr::branch(idr::Token(values[held.token]), paths));
      if (branched.back().size() != model.handles)
        fail("a branch into " + std::to_string(paths) + " regions gave " +
             std::to_string(branched.back().size()) + " handles");
    }
    if (why.empty()) {
      // Every handle given out and every one consumed, by the region that
      // holds it and its token's number.
      std::vector<std::pair<unsigned, unsigned>> given, consumed;
      llvm::SmallVector<idr::Available<Size>> arms;
      std::vector<unsigned> regionOf;
      for (unsigned r = 0; r < paths; ++r) {
        const Region &region = c.regions[r];
        idr::Available<Size> holds;
        for (const Named &held : region.holds) {
          given.emplace_back(r, held.token);
          if (held.token < c.before.size())
            holds.tokens.emplace_back(held.size, std::move(branched[held.token][r]));
          else
            holds.tokens.emplace_back(held.size, idr::Token(values[held.token]));
        }
        for (unsigned token : region.freed) {
          given.emplace_back(r, token);
          consumed.emplace_back(r, numberOf(std::move(branched[token][r]).consume()));
        }
        if (region.end == End::Leaves) {
          for (auto &held : holds.tokens)
            consumed.emplace_back(r, numberOf(std::move(held.second).consume()));
          continue;
        }
        regionOf.push_back(r);
        arms.push_back(std::move(holds));
      }
      // A token a callback names by a position past the rejoining regions
      // is held by a region past the last, which holds none.
      auto regionAt = [&](std::size_t arm) {
        return arm < regionOf.size() ? regionOf[arm] : paths;
      };
      std::vector<Joined> joins;
      std::vector<Dropped> drops;
      llvm::SmallVector<Size> back = idr::rejoin(
          std::move(arms), [&](const Size &s) -> std::uint32_t { return c.wanted[s]; },
          [&](const Size &s, llvm::SmallVector<idr::Token> tokens) {
            Joined j{s, {}};
            for (std::size_t arm = 0; arm < tokens.size(); ++arm) {
              unsigned number = numberOf(std::move(tokens[arm]).consume());
              j.tokens.push_back(number);
              consumed.emplace_back(regionAt(arm), number);
            }
            joins.push_back(std::move(j));
          },
          [&](unsigned arm, const Size &s, idr::Token token) {
            unsigned number = numberOf(std::move(token).consume());
            drops.push_back({arm, s, number});
            consumed.emplace_back(regionAt(arm), number);
          });
      std::ranges::sort(given);
      std::ranges::sort(consumed);
      if (consumed != given)
        fail("the handles consumed are not those given out, each once to its own token");
      std::vector<Size> made;
      for (const Joined &j : joins)
        made.push_back(j.size);
      if (std::vector<Size>(back.begin(), back.end()) != made)
        fail("the rejoin gave back other sizes than those of its joins, in order");
      for (Size s : idr::allOf<Size>()) {
        std::vector<Joined> ofSize;
        for (const Joined &j : joins)
          if (j.size == s)
            ofSize.push_back(j);
        if (ofSize != model.joins[s])
          fail(std::string(sizeNames[s]) + " joined " + describe(ofSize) + ", the model " +
               describe(model.joins[s]));
      }
      std::ranges::sort(drops);
      if (drops != model.drops)
        fail("the drops are not the model's");
    }
    if (why.empty())
      continue;
    ++failures;
    if (report == Report::Each)
      ADD_FAILURE() << "seed " << seed << ":" << why << "\nin the case:" << describe(c);
  }
  return failures;
}

TEST(Token, EveryCaseAgainstItsRegions) { EXPECT_EQ(judge<Plant::None>(10, Report::Each), 0u); }

// The judgement can fail: each model with a planted fault disagrees with
// the handle on some case.
TEST(Token, EachMutantModelIsCaught) {
  EXPECT_GT(judge<Plant::AlwaysAPath>(1, Report::None), 0u);
  EXPECT_GT(judge<Plant::Uncapped>(1, Report::None), 0u);
  EXPECT_GT(judge<Plant::FirstRegionOnly>(1, Report::None), 0u);
  EXPECT_GT(judge<Plant::LastFirst>(1, Report::None), 0u);
  EXPECT_GT(judge<Plant::NothingJoinsAll>(1, Report::None), 0u);
  EXPECT_GT(judge<Plant::DropsShifted>(1, Report::None), 0u);
}

} // namespace
