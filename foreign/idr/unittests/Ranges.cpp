// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// NEEDS-ACCEPTANCE: that every range rule holds over its whole box: bounded keeps exactly the bounds inside the small range, rangeOf and boundsOf round-trip, and add, sub, mul, ofInteger and boundsOf hold every member, each present bound small and exact where the rule promises it.
// The box of the range rules (idr::ranges): each rule called on every
// interval over a domain where its behaviour changes, against the exact value
// of every member in __int128. A missing bound holds anything; its members
// are integers outside the small range on that side.

#include "idr/IR/Ranges.h"

#include "idris_rt.h"

#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/STLExtras.h"

#include "gtest/gtest.h"

#include <algorithm>
#include <cstdint>
#include <functional>
#include <optional>
#include <vector>

using idr::ranges::Bounds;
using llvm::APInt;
using mlir::ConstantIntRanges;

namespace ranges = idr::ranges;

namespace {

using i128 = __int128;

// The fixture of each test, googletest's hook around it: SetUp reads the
// runtime's live cells and TearDown expects them again, and no failing
// input. A box can fail on millions of inputs, and an assertion reports
// each; googletest has none that counts, so `check` counts them and reports
// the first with every operand.
class Ranges : public testing::Test {
public:
  template <typename Operands>
  void check(bool holds, Operands operands) {
    if (!holds && failures++ == 0)
      ADD_FAILURE() << operands();
  }

protected:
  void SetUp() override { live = idris_rt_live_cells(); }
  void TearDown() override {
    EXPECT_EQ(failures, 0u);
    EXPECT_EQ(idris_rt_live_cells(), live);
  }

private:
  uint64_t live = 0;
  unsigned failures = 0;
};

// D64: each end of the small range with two neighbours inside it, and 0 with
// two either side. The rules act only where a bound leaves the small range
// (bounded), a product leaves i64 (checkedMul) or a sign changes (the corners
// of a product).
constexpr int64_t d64[] = {
    IDRIS_RT_SMALL_MIN,     IDRIS_RT_SMALL_MIN + 1, IDRIS_RT_SMALL_MIN + 2, -2, -1, 0, 1, 2,
    IDRIS_RT_SMALL_MAX - 2, IDRIS_RT_SMALL_MAX - 1, IDRIS_RT_SMALL_MAX};

// OUT: what a missing bound stands for, below the small range and above it:
// the nearest integer outside it and the end of i64.
constexpr int64_t out[] = {IDRIS_RT_SMALL_MIN - 1, INT64_MIN, IDRIS_RT_SMALL_MAX + 1,
                           INT64_MAX};

// Every exact result in this box, of one or two values of at most 64 bits,
// is at most 2^126 in magnitude: a search for the least and the greatest
// starts just beyond.
constexpr i128 above = (i128{1} << 126) + 1;
constexpr i128 below = -above;

bool small(i128 v) { return v >= IDRIS_RT_SMALL_MIN && v <= IDRIS_RT_SMALL_MAX; }

// The bound a value is, in the coordinate Bounds keeps: itself inside the
// small range, none outside it.
std::optional<int64_t> asBound(i128 v) {
  return small(v) ? std::optional<int64_t>(static_cast<int64_t>(v)) : std::nullopt;
}

// Whether `v` is within `b`: a missing bound holds anything.
bool within(i128 v, Bounds b) { return (!b.lo || *b.lo <= v) && (!b.hi || v <= *b.hi); }

// Whether every bound `b` gives is inside the small range, as Bounds states.
bool boundsSmall(Bounds b) { return (!b.lo || small(*b.lo)) && (!b.hi || small(*b.hi)); }

bool sameBounds(Bounds a, Bounds b) { return a.lo == b.lo && a.hi == b.hi; }

// Bounds has no printer, and its namespace, where googletest looks for one,
// is not this unit's.
testing::Message &operator<<(testing::Message &m, Bounds b) {
  return m << "[" << b.lo << ", " << b.hi << "]";
}

// Every interval over D64: each bound a point or none, ordered when both are
// given.
template <typename Fn>
void eachInterval(Fn fn) {
  std::vector<std::optional<int64_t>> ends{std::nullopt};
  ends.insert(ends.end(), std::begin(d64), std::end(d64));
  for (std::optional<int64_t> lo : ends)
    for (std::optional<int64_t> hi : ends)
      // An empty interval is no interval of a value.
      if (!lo || !hi || *lo <= *hi)
        fn(Bounds{lo, hi});
}

// The members of an interval: the points of D64 and of OUT within it.
template <typename Fn>
void eachMember(Bounds b, Fn fn) {
  for (int64_t v : d64)
    if (within(v, b))
      fn(v);
  for (int64_t v : out)
    if (within(v, b))
      fn(v);
}

// `bounds` on every pair of intervals over D64: its result holds `op` of
// every member pair and each of its present bounds is small; `exact` then
// gets the operands, the result and the least and greatest of `op`.
template <typename BoundsFn, typename Op, typename Exact>
void checkArithmetic(Ranges &box, BoundsFn bounds, Op op, Exact exact) {
  eachInterval([&](Bounds a) {
    eachInterval([&](Bounds b) {
      Bounds r = bounds(a, b);
      box.check(boundsSmall(r), [&] {
        return testing::Message() << "a " << a << ", b " << b << ": " << r;
      });
      i128 least = above, greatest = below;
      eachMember(a, [&](int64_t x) {
        eachMember(b, [&](int64_t y) {
          i128 e = op(i128{x}, i128{y});
          least = std::min(least, e);
          greatest = std::max(greatest, e);
          box.check(within(e, r), [&] {
            return testing::Message() << "a " << a << ", b " << b << ", x " << x << ", y " << y;
          });
        });
      });
      exact(a, b, r, least, greatest);
    });
  });
}

TEST_F(Ranges, Bounded) {
  std::vector<std::optional<int64_t>> ends{std::nullopt};
  ends.insert(ends.end(), std::begin(d64), std::end(d64));
  ends.insert(ends.end(), std::begin(out), std::end(out));
  // A bound is kept where it is one, inside the small range.
  auto kept = [](std::optional<int64_t> v) { return v ? asBound(*v) : std::nullopt; };
  for (std::optional<int64_t> lo : ends)
    for (std::optional<int64_t> hi : ends)
      check(sameBounds(ranges::bounded(lo, hi), Bounds{kept(lo), kept(hi)}),
            [&] { return testing::Message() << "lo " << lo << ", hi " << hi; });
}

TEST_F(Ranges, RangeOfRoundTrips) {
  eachInterval([&](Bounds b) {
    ConstantIntRanges r = ranges::rangeOf(b);
    auto operands = [&] { return testing::Message() << "b " << b << ": " << r; };
    check(sameBounds(ranges::boundsOf(r), b), operands);
    eachMember(b, [&](int64_t v) {
      APInt word(64, static_cast<uint64_t>(v), /*isSigned=*/true);
      check(r.smin().getBitWidth() == 64 && r.smin().sle(word) && word.sle(r.smax()), operands);
    });
  });
}

// The operands and the result of add, sub or mul, where it is not as exact
// as it promises.
auto report(Bounds a, Bounds b, Bounds r) {
  return [=] { return testing::Message() << "a " << a << ", b " << b << ": " << r; };
}

TEST_F(Ranges, Add) {
  checkArithmetic(*this, ranges::add, std::plus<i128>(),
                  [&](Bounds a, Bounds b, Bounds r, i128 least, i128 greatest) {
                    // Exact on each side both operands bound.
                    if (a.lo && b.lo)
                      check(r.lo == asBound(least), report(a, b, r));
                    if (a.hi && b.hi)
                      check(r.hi == asBound(greatest), report(a, b, r));
                  });
}

TEST_F(Ranges, Sub) {
  checkArithmetic(*this, ranges::sub, std::minus<i128>(),
                  [&](Bounds a, Bounds b, Bounds r, i128 least, i128 greatest) {
                    // The least difference takes b's greatest member, and
                    // the greatest its least.
                    if (a.lo && b.hi)
                      check(r.lo == asBound(least), report(a, b, r));
                    if (a.hi && b.lo)
                      check(r.hi == asBound(greatest), report(a, b, r));
                  });
}

TEST_F(Ranges, Mul) {
  checkArithmetic(*this, ranges::mul, std::multiplies<i128>(),
                  [&](Bounds a, Bounds b, Bounds r, i128 least, i128 greatest) {
                    // Exact when every bound is known and every member
                    // product is an i64.
                    if (!a.fits() || !b.fits() || least < INT64_MIN || greatest > INT64_MAX)
                      return;
                    Bounds e = ranges::bounded(static_cast<int64_t>(least),
                                               static_cast<int64_t>(greatest));
                    check(sameBounds(r, e), report(a, b, r));
                  });
}

// A reading of a word, signed or unsigned: the flag ofInteger takes, the
// range it makes of two ends, its order of words and a word's value.
struct Reading {
  bool isSigned;
  ConstantIntRanges (*make)(const APInt &, const APInt &);
  bool (*ordered)(const APInt &, const APInt &);
  i128 (*value)(const APInt &);
};

constexpr Reading readings[] = {
    {true, &ConstantIntRanges::fromSigned,
     [](const APInt &a, const APInt &b) { return a.sle(b); },
     [](const APInt &v) -> i128 { return v.getSExtValue(); }},
    {false, &ConstantIntRanges::fromUnsigned,
     [](const APInt &a, const APInt &b) { return a.ule(b); },
     [](const APInt &v) -> i128 { return v.getZExtValue(); }},
};

// The widths of the small-width domain; at the first four, every range.
constexpr unsigned widths[] = {1, 2, 3, 4, 5, 6, 7, 8, 64};
constexpr unsigned freeWidths[] = {1, 2, 3, 4};

// The values a range of `width` is checked on: every one up to 8 bits. At
// 64, signed: D64 and the ends of i64; unsigned: where a bound leaves the
// small range (one past its top) or i64 (INT64_MAX + 1), and the ends of
// u64.
std::vector<APInt> candidates(unsigned width) {
  std::vector<APInt> values;
  if (width < 64) {
    for (uint64_t v = 0; v < (uint64_t{1} << width); ++v)
      values.emplace_back(width, v);
    return values;
  }
  for (int64_t v : d64)
    values.emplace_back(64, static_cast<uint64_t>(v), /*isSigned=*/true);
  for (int64_t v : {INT64_MIN, INT64_MAX})
    values.emplace_back(64, static_cast<uint64_t>(v), /*isSigned=*/true);
  constexpr uint64_t u = IDRIS_RT_SMALL_MAX;
  for (uint64_t v : {uint64_t{0}, uint64_t{1}, uint64_t{2}, u - 1, u, u + 1, uint64_t{INT64_MAX},
                     uint64_t{INT64_MAX} + 1, UINT64_MAX - 1, UINT64_MAX})
    values.emplace_back(64, v);
  return values;
}

// A member of a range: a value of its width within both its unsigned and its
// signed bounds.
bool member(const ConstantIntRanges &r, const APInt &v) {
  return r.umin().getBitWidth() == v.getBitWidth() && r.umin().ule(v) && v.ule(r.umax()) &&
         r.smin().sle(v) && v.sle(r.smax());
}

// Every range over `values` with a member.
template <typename Fn>
void eachFree(const std::vector<APInt> &values, Fn fn) {
  for (const APInt &umin : values)
    for (const APInt &umax : values)
      for (const APInt &smin : values)
        for (const APInt &smax : values) {
          if (!umin.ule(umax) || !smin.sle(smax))
            continue;
          ConstantIntRanges r(umin, umax, smin, smax);
          // A range with no member is the range of no value.
          if (llvm::any_of(values, [&](const APInt &v) { return member(r, v); }))
            fn(r);
        }
}

// Every range `reading` makes of two of `values` ordered as it reads them.
template <typename Fn>
void eachMade(const std::vector<APInt> &values, const Reading &reading, Fn fn) {
  for (const APInt &lo : values)
    for (const APInt &hi : values)
      if (reading.ordered(lo, hi))
        fn(reading.make(lo, hi));
}

TEST_F(Ranges, OfInteger) {
  // Under either reading of any range: every member within, each bound small.
  auto sound = [&](const std::vector<APInt> &values, const ConstantIntRanges &r) {
    for (const Reading &reading : readings) {
      Bounds b = ranges::ofInteger(r, reading.isSigned);
      auto operands = [&] {
        return testing::Message() << r << ", signed " << reading.isSigned << ": " << b;
      };
      check(boundsSmall(b), operands);
      for (const APInt &v : values)
        if (member(r, v))
          check(within(reading.value(v), b), operands);
    }
  };
  for (unsigned width : freeWidths) {
    std::vector<APInt> values = candidates(width);
    eachFree(values, [&](const ConstantIntRanges &r) { sound(values, r); });
  }
  // A range a reading made, read so, has the extremes of its members where
  // they are small.
  for (unsigned width : widths) {
    std::vector<APInt> values = candidates(width);
    for (const Reading &made : readings)
      eachMade(values, made, [&](const ConstantIntRanges &r) {
        sound(values, r);
        i128 least = above, greatest = below;
        for (const APInt &v : values)
          if (member(r, v)) {
            least = std::min(least, made.value(v));
            greatest = std::max(greatest, made.value(v));
          }
        Bounds b = ranges::ofInteger(r, made.isSigned);
        check(sameBounds(b, Bounds{asBound(least), asBound(greatest)}), [&] {
          return testing::Message() << r << ", signed " << made.isSigned << ": " << b;
        });
      });
  }
}

TEST_F(Ranges, BoundsOf) {
  // At 64 bits, the signed bounds where they are small, which hold every
  // member; at any other width a range is of no big, and states none.
  auto states = [&](const std::vector<APInt> &values, const ConstantIntRanges &r) {
    Bounds b = ranges::boundsOf(r);
    auto operands = [&] { return testing::Message() << r << ": " << b; };
    if (r.smin().getBitWidth() != 64) {
      check(!b.lo && !b.hi, operands);
      return;
    }
    Bounds e{asBound(r.smin().getSExtValue()), asBound(r.smax().getSExtValue())};
    check(sameBounds(b, e), operands);
    for (const APInt &v : values)
      if (member(r, v))
        check(within(v.getSExtValue(), b), operands);
  };
  for (unsigned width : freeWidths) {
    std::vector<APInt> values = candidates(width);
    eachFree(values, [&](const ConstantIntRanges &r) { states(values, r); });
  }
  for (unsigned width : widths) {
    std::vector<APInt> values = candidates(width);
    for (const Reading &made : readings)
      eachMade(values, made, [&](const ConstantIntRanges &r) { states(values, r); });
  }
}

} // namespace
