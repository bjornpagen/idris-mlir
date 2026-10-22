// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cases of the token handle's box (idr/Testing/TokenCases.h), built
// from a seed: the case's own weights drawn first, so one case leans hard
// on one size, on freeing at a region's head or on leaving, and the next
// on another; each born token placed anywhere among what its region holds.

#include "idr/Testing/TokenCases.h"

#include "idr/Support/Enum.h"
#include "idr/Testing/Draws.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <utility>

namespace {

// What a region does with a token held before the op: keeps it, or frees
// it at its head.
enum class Keep : std::uint8_t { Kept, Freed };

} // namespace

template <>
struct idr::EnumTraits<Keep> {
  static constexpr std::size_t count = 2;
};

namespace idr::box::tokens {

namespace {

// The most of one size the code after the op wants.
constexpr unsigned mostWanted = 3;

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

} // namespace

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
  for (Size s : allOf<Size>())
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
  for (Size s : allOf<Size>())
    text += " " + std::string(sizeNames[s]) + " " + std::to_string(c.wanted[s]);
  return text;
}

} // namespace idr::box::tokens
