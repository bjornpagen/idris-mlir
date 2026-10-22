// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The cases of the interval box: a width of Idris's integers, and operands
// of it, each an interval made in one of four shapes from two ends, with
// members of it. How often each shape and each source of a point comes is
// drawn first from the case's seed.

#include "idr/IR/Numeric/Word.h"
#include "idr/Support/Enum.h"
#include "idr/Testing/Box.h"
#include "idr/Testing/Draws.h"
#include "idr/Testing/IntervalCases.h"

#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "llvm/ADT/APInt.h"

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <utility>
#include <vector>

namespace {

// How an operand's interval is made.
enum class Shape : std::uint8_t { Constant, Signed, Unsigned, Whole };
// Where an end or a member is drawn from: the points where the meanings
// change, or anywhere.
enum class Source : std::uint8_t { Edge, Random };

} // namespace

template <>
struct idr::EnumTraits<Shape> {
  static constexpr std::size_t count = 4;
};
template <>
struct idr::EnumTraits<Source> {
  static constexpr std::size_t count = 2;
};

namespace {

using idr::EnumArray;
using idr::box::Draws;
using idr::box::member;
using idr::box::intervals::Case;
using idr::box::intervals::Operand;
using idr::numeric::Word;
using idr::numeric::Words;
using llvm::APInt;
using mlir::ConstantIntRanges;

// The widths of Idris's integers, and how many points a member list draws
// beyond its interval's ends.
constexpr unsigned widths[] = {8, 16, 32, 64};
constexpr unsigned drawnMembers = 3;

// How often each choice comes in one case, drawn first from its seed, the
// first case of each choice at least once in four.
struct Swarm {
  EnumArray<Shape, unsigned> shape;
  EnumArray<Source, unsigned> source;

  explicit Swarm(Draws &draws)
      : shape{{1 + draws.below(4), draws.below(5), draws.below(5), draws.below(3)}},
        source{{1 + draws.below(4), draws.below(3)}} {}
};

// The points of width `w` where some meaning changes, each a word's bits.
std::vector<std::uint64_t> edgesAt(unsigned w) {
  std::uint64_t least = Words{}.least(Words::of(0, w)).bits;
  std::uint64_t width = w;
  std::vector<std::uint64_t> points;
  for (std::uint64_t point :
       {std::uint64_t{0}, std::uint64_t{1}, std::uint64_t{2}, ~std::uint64_t{0},
        ~std::uint64_t{0} - 1, least, least + 1, least + 2, least - 1, least - 2, least - 3,
        width - 1, width, width + 1, std::uint64_t{0} - width, std::uint64_t{0xD7FF},
        std::uint64_t{0xD800}, std::uint64_t{0xDFFF}, std::uint64_t{0xE000},
        std::uint64_t{0x10FFFF}, std::uint64_t{0x110000}, std::uint64_t{1} << 32,
        (std::uint64_t{1} << 32) + 0x41})
    points.push_back(Words::of(point, w).bits);
  return points;
}

// Every bit of a word drawn at random.
std::uint64_t random64(Draws &draws) {
  std::uint64_t high = draws.below(std::size_t{1} << 32);
  std::uint64_t low = draws.below(std::size_t{1} << 32);
  return high << 32 | low;
}

// A point of width `w`, drawn from where the case's weights say.
std::uint64_t pointAt(Draws &draws, const Swarm &swarm, const std::vector<std::uint64_t> &edges,
                      unsigned w) {
  if (draws.weighted(swarm.source) == Source::Edge)
    return edges[draws.below(edges.size())];
  return Words::of(random64(draws), w).bits;
}

// An interval of width `w` with ends `a` and `b`, made as each shape makes
// one; each range reads its ends in its own order.
using Make = ConstantIntRanges (*)(std::uint64_t, std::uint64_t, unsigned);
constexpr EnumArray<Shape, Make> makers{
    {[](std::uint64_t a, std::uint64_t, unsigned w) {
       return ConstantIntRanges::constant(APInt(w, a));
     },
     [](std::uint64_t a, std::uint64_t b, unsigned w) {
       if (Words::signedOf(Word{b, w}) < Words::signedOf(Word{a, w}))
         std::swap(a, b);
       return ConstantIntRanges::fromSigned(APInt(w, a), APInt(w, b));
     },
     [](std::uint64_t a, std::uint64_t b, unsigned w) {
       if (b < a)
         std::swap(a, b);
       return ConstantIntRanges::fromUnsigned(APInt(w, a), APInt(w, b));
     },
     [](std::uint64_t, std::uint64_t, unsigned w) { return ConstantIntRanges::maxRange(w); }}};

// A point from `lo` up to `hi`, of width `w`, read in the order in which
// `lo` is the least: the distance from it, drawn, wraps to the width.
std::uint64_t within(Draws &draws, const APInt &lo, const APInt &hi, unsigned w) {
  std::uint64_t span = (hi.getZExtValue() - lo.getZExtValue()) & Words::mask(w);
  std::uint64_t offset = span == Words::mask(w) ? random64(draws) : random64(draws) % (span + 1);
  return Words::of(lo.getZExtValue() + offset, w).bits;
}

Operand operandOf(Draws &draws, const Swarm &swarm, const std::vector<std::uint64_t> &edges,
                  unsigned w) {
  std::uint64_t a = pointAt(draws, swarm, edges, w);
  std::uint64_t b = pointAt(draws, swarm, edges, w);
  ConstantIntRanges interval = makers[draws.weighted(swarm.shape)](a, b, w);
  std::vector<std::uint64_t> points{
      interval.umin().getZExtValue(), interval.umax().getZExtValue(),
      interval.smin().getZExtValue(), interval.smax().getZExtValue()};
  for (unsigned k = 0; k < drawnMembers; ++k)
    points.push_back(pointAt(draws, swarm, edges, w));
  points.push_back(within(draws, interval.smin(), interval.smax(), w));
  points.push_back(within(draws, interval.umin(), interval.umax(), w));
  std::ranges::sort(points);
  points.erase(std::ranges::unique(points).begin(), points.end());
  Operand operand{interval, {}};
  for (std::uint64_t point : points)
    if (member(interval, APInt(w, point)))
      operand.members.push_back(Word{point, w});
  return operand;
}

} // namespace

Case idr::box::intervals::caseOf(std::uint64_t seed, unsigned operands) {
  Draws draws(seed);
  Swarm swarm(draws);
  unsigned w = widths[draws.below(std::size(widths))];
  std::vector<std::uint64_t> edges = edgesAt(w);
  Case drawn{w, {}};
  for (unsigned k = 0; k < operands; ++k)
    drawn.operands.push_back(operandOf(draws, swarm, edges, w));
  return drawn;
}
