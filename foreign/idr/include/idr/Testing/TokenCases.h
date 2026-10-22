// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cases of the token handle's box: each an op that runs exactly one of
// its regions, built from a seed, as data. Up to three tokens are held
// before it, each branched into every region; each region keeps some of
// them and frees the rest at its head, holds tokens born in it, and either
// rejoins the op at its results or leaves it another way, freeing what it
// holds; the code after the op wants a few of each size. A token is named
// by its number, which the box maps to a value of its own.
#ifndef IDR_TESTING_TOKENCASES_H
#define IDR_TESTING_TOKENCASES_H

#include "idr/Support/Enum.h"

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace idr::box::tokens {

// The sizes a case's tokens are of: the layouts the rejoin is over.
enum class Size : std::uint8_t { Small, Middle, Large };
// How a region ends: rejoining the op at its results, or leaving it another
// way (a return, a jump), which frees what it holds.
enum class End : std::uint8_t { Rejoins, Leaves };

} // namespace idr::box::tokens

template <>
struct idr::EnumTraits<idr::box::tokens::Size> {
  static constexpr std::size_t count = 3;
};
template <>
struct idr::EnumTraits<idr::box::tokens::End> {
  static constexpr std::size_t count = 2;
};

namespace idr::box::tokens {

inline constexpr EnumArray<Size, const char *> sizeNames{{"small", "middle", "large"}};

// The most tokens held before the op, regions, and tokens born in one
// region; and so every token a case can name.
inline constexpr unsigned mostBefore = 3;
inline constexpr unsigned mostRegions = 4;
inline constexpr unsigned mostBorn = 3;
inline constexpr unsigned mostTokens = mostBefore + mostRegions * mostBorn;

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

// The case of `seed`, the same on every target.
Case caseOf(std::uint64_t seed);

// The case as a failure prints it.
std::string describe(const Case &c);

} // namespace idr::box::tokens

#endif // IDR_TESTING_TOKENCASES_H
