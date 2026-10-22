// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the footprint (idr/Support/Footprint.h): each run's measured
// footprint against the trace of what was held, on cases drawn from seeds.
// A case is a list of steps over things of each counted kind (a vector of
// the vocabulary, a hashed map, a hashed set, an arena) and runs nested
// inside one another. The model reads each thing's bytes off the thing
// itself, a vector's capacity, a map's or a set's memory size, an arena's
// total memory, which is LLVM's and the library's own account of what they
// hold; all it knows besides is how each kind grows: a vector, a map and a
// set move into storage that replaces theirs, holding both while they move,
// and an arena adds a slab. The judgement is shown failing on each model
// planted with one fault, among them each kind of storage counting nothing.

#include "idr/Support/Enum.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Match.h"
#include "idr/Testing/Draws.h"

#include "llvm/Support/Alignment.h"

#include "gtest/gtest.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <string>
#include <utility>
#include <variant>
#include <vector>

namespace {

// What a step of a case does: a thing made, one grown, one copied, one
// dropped, a run begun, the innermost run ended.
enum class Step : std::uint8_t { Make, Grow, Copy, Drop, Begin, End };
// The kinds of counted storage.
enum class Kind : std::uint8_t { Vector, Map, Set, Arena };

} // namespace

template <>
struct idr::EnumTraits<Step> {
  static constexpr std::size_t count = 6;
};
template <>
struct idr::EnumTraits<Kind> {
  static constexpr std::size_t count = 4;
};

namespace {

using idr::EnumArray;
using idr::box::Draws;

using Elements = idr::footprint::Vector<std::uint32_t>;
using Map = idr::footprint::DenseMap<std::uint32_t, std::uint32_t>;
using Set = idr::footprint::DenseSet<std::uint32_t>;
using Arena = idr::footprint::BumpPtrAllocator;
using Thing = std::variant<Elements, Map, Set, Arena>;

// The number of seeds a case is drawn from, the most steps one draws, the
// most growths a step makes, and the most bytes one allocation in an arena
// asks: past a slab, so some take a slab of their own.
constexpr std::uint64_t seeds = 500;
constexpr unsigned mostSteps = 24;
constexpr unsigned mostGrowths = 100;
constexpr unsigned mostBytes = 6000;

// How a kind grows: into storage that replaces its storage, the two held at
// once while it moves, or by storage added beside what it holds.
enum class Growth : std::uint8_t { Replaces, Adds };
constexpr EnumArray<Kind, Growth> growthOf{
    {Growth::Replaces, Growth::Replaces, Growth::Replaces, Growth::Adds}};

Kind kindOf(const Thing &thing) {
  return idr::match(
      thing, [](const Elements &) { return Kind::Vector; }, [](const Map &) { return Kind::Map; },
      [](const Set &) { return Kind::Set; }, [](const Arena &) { return Kind::Arena; });
}

// The bytes a thing holds, by its own account.
std::int64_t bytesOf(const Thing &thing) {
  auto bytes = idr::match(
      thing, [](const Elements &v) { return v.capacity() * sizeof(std::uint32_t); },
      [](const Map &m) { return m.getMemorySize(); },
      [](const Set &s) { return s.getMemorySize(); },
      [](const Arena &a) { return a.getTotalMemory(); });
  return static_cast<std::int64_t>(bytes);
}

// An empty thing of each kind, which holds nothing until it grows.
using Make = Thing (*)();
constexpr EnumArray<Kind, Make> makers{{[] { return Thing(std::in_place_type<Elements>); },
                                        [] { return Thing(std::in_place_type<Map>); },
                                        [] { return Thing(std::in_place_type<Set>); },
                                        [] { return Thing(std::in_place_type<Arena>); }}};

// How often each choice comes in one case, drawn first from its seed, the
// first case of each choice at least once in four.
struct Swarm {
  EnumArray<Step, unsigned> step;
  EnumArray<Kind, unsigned> kind;

  explicit Swarm(Draws &draws)
      : step{{1 + draws.below(4), draws.below(6), draws.below(4), draws.below(4), draws.below(4),
              draws.below(4)}},
        kind{{1 + draws.below(4), draws.below(5), draws.below(5), draws.below(5)}} {}
};

// The fault a model of the footprint is planted with, if any, in how it
// follows runs and the storage it counts.
enum class Plant : std::uint8_t { None, EndsOnly, InnerForgotten, CopiesFree, ReplacedInPlace };

// What a judge takes for each run's footprint, read off the trace of what
// is held: the most bytes held while the run was open beyond what was held
// when it began. A mutant's is wrong in one way, and the judge must say so:
// what the run ended holding, an outer run blind to its inner runs, a copy
// that takes nothing, storage replaced by freeing the old before taking the
// new; or, apart from its plant, a kind of storage, one of `Uncounted`,
// that counts nothing.
template <Plant P, Kind... Uncounted>
class Model {
public:
  void made(Kind kind, std::int64_t bytes) {
    things.push_back({kind, counted(kind, bytes)});
    raise(held());
  }
  void copied(Kind kind, std::int64_t bytes) {
    things.push_back({kind, P == Plant::CopiesFree ? 0 : counted(kind, bytes)});
    raise(held());
  }
  // Thing `at` grew to hold `bytes`; a growth that took no storage held
  // nothing more.
  void grew(std::size_t at, std::int64_t bytes) {
    Kept &thing = things[at];
    std::int64_t now = counted(thing.kind, bytes);
    if (now == thing.bytes)
      return;
    if (growthOf[thing.kind] == Growth::Replaces && P != Plant::ReplacedInPlace)
      raise(held() + now);
    thing.bytes = now;
    raise(held());
  }
  void dropped(std::size_t at) { things.erase(things.begin() + static_cast<std::ptrdiff_t>(at)); }
  void begin() { runs.push_back({held(), held()}); }
  std::int64_t end() {
    Open run = runs.back();
    runs.pop_back();
    if constexpr (P == Plant::EndsOnly)
      return held() - run.start;
    else
      return run.peak - run.start;
  }

private:
  struct Kept {
    Kind kind;
    std::int64_t bytes;
  };
  struct Open {
    std::int64_t start;
    std::int64_t peak;
  };

  std::int64_t counted(Kind kind, std::int64_t bytes) const {
    return ((kind == Uncounted) || ...) ? 0 : bytes;
  }
  std::int64_t held() const {
    std::int64_t sum = 0;
    for (const Kept &thing : things)
      sum += thing.bytes;
    return sum;
  }
  // Every open run's peak raised to `bytes`, held at some moment.
  void raise(std::int64_t bytes) {
    if constexpr (P == Plant::InnerForgotten) {
      if (!runs.empty())
        runs.back().peak = std::max(runs.back().peak, bytes);
    } else {
      for (Open &run : runs)
        run.peak = std::max(run.peak, bytes);
    }
  }

  std::vector<Kept> things;
  std::vector<Open> runs;
};

// Whether a failing case is reported: by the box's own judgement, each;
// by a mutant's, none, since a mutant must fail.
enum class Report : std::uint8_t { Each, None };

// The cases, over every seed up to `limit` of them, where a run's measured
// footprint differs from the model's. The runs still open at a case's end
// are ended in turn, and its things are dropped after them.
template <Plant P, Kind... Uncounted>
unsigned judge(unsigned limit, Report report) {
  unsigned failures = 0;
  for (std::uint64_t seed = 1; seed <= seeds && failures < limit; ++seed) {
    Draws draws(seed);
    Swarm swarm(draws);
    // Room for every thing a case can make, so no thing moves as one is
    // added beside it.
    std::vector<Thing> held;
    held.reserve(mostSteps);
    std::vector<idr::footprint::Run> runs;
    Model<P, Uncounted...> model;
    std::string why;
    auto end = [&] {
      auto measured = static_cast<std::int64_t>(runs.back().end());
      runs.pop_back();
      std::int64_t expected = model.end();
      if (measured != expected && why.empty())
        why = "a run at depth " + std::to_string(runs.size()) + " measured " +
              std::to_string(measured) + " bytes, its model " + std::to_string(expected);
    };
    for (unsigned steps = draws.below(mostSteps + 1); steps > 0; --steps) {
      EnumArray<Step, unsigned> open = swarm.step;
      if (held.empty())
        open[Step::Grow] = open[Step::Copy] = open[Step::Drop] = 0;
      if (runs.empty())
        open[Step::End] = 0;
      switch (draws.weighted(open)) {
      case Step::Make: {
        Kind kind = draws.weighted(swarm.kind);
        held.push_back(makers[kind]());
        model.made(kind, bytesOf(held.back()));
        break;
      }
      case Step::Grow: {
        std::size_t at = draws.below(held.size());
        for (unsigned n = draws.below(mostGrowths + 1); n > 0; --n) {
          idr::match(
              held[at], [&](Elements &v) { v.push_back(draws.below(1000)); },
              [](Map &m) { m.try_emplace(static_cast<std::uint32_t>(m.size()), 0u); },
              [](Set &s) { s.insert(static_cast<std::uint32_t>(s.size())); },
              [&](Arena &a) { (void)a.Allocate(1 + draws.below(mostBytes), llvm::Align(8)); });
          model.grew(at, bytesOf(held[at]));
        }
        break;
      }
      // An arena is never copied, and stays as it is.
      case Step::Copy: {
        auto keep = [&](Thing copy) {
          held.push_back(std::move(copy));
          model.copied(kindOf(held.back()), bytesOf(held.back()));
        };
        idr::match(
            held[draws.below(held.size())],
            [&](const Elements &v) { keep(Thing(std::in_place_type<Elements>, v)); },
            [&](const Map &m) { keep(Thing(std::in_place_type<Map>, m)); },
            [&](const Set &s) { keep(Thing(std::in_place_type<Set>, s)); }, [](const Arena &) {});
        break;
      }
      case Step::Drop: {
        std::size_t at = draws.below(held.size());
        held.erase(held.begin() + static_cast<std::ptrdiff_t>(at));
        model.dropped(at);
        break;
      }
      case Step::Begin:
        runs.push_back(idr::footprint::Run::begin());
        model.begin();
        break;
      case Step::End:
        end();
        break;
      }
    }
    while (!runs.empty())
      end();
    if (why.empty())
      continue;
    ++failures;
    if (report == Report::Each)
      ADD_FAILURE() << "seed " << seed << ": " << why;
  }
  return failures;
}

TEST(Footprint, EachRunAgainstTheTraceOfWhatWasHeld) {
  EXPECT_EQ(judge<Plant::None>(10, Report::Each), 0u);
}

// The judgement can fail: each model with a planted fault disagrees with
// the measure on some case.
TEST(Footprint, EachMutantModelIsCaught) {
  EXPECT_GT(judge<Plant::EndsOnly>(1, Report::None), 0u);
  EXPECT_GT(judge<Plant::InnerForgotten>(1, Report::None), 0u);
  EXPECT_GT(judge<Plant::CopiesFree>(1, Report::None), 0u);
  EXPECT_GT(judge<Plant::ReplacedInPlace>(1, Report::None), 0u);
  EXPECT_GT((judge<Plant::None, Kind::Map>(1, Report::None)), 0u);
  EXPECT_GT((judge<Plant::None, Kind::Set>(1, Report::None)), 0u);
  EXPECT_GT((judge<Plant::None, Kind::Arena>(1, Report::None)), 0u);
}

} // namespace
