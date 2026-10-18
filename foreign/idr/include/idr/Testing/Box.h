// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The exhaustive boxes' one test API: the fixture every box's tests share,
// the bigs a test owns and the readings of what the runtime gives back, the
// reduced domains a box walks, the walks over their intervals and members,
// and the printers a failure is reported with. Each box holds only its own
// rule's tests.
#ifndef IDR_TESTING_BOX_H
#define IDR_TESTING_BOX_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"

#include "idris_rt.h"

#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/ArrayRef.h"

#include "gtest/gtest.h"

#include <algorithm>
#include <cstdint>
#include <iterator>
#include <optional>
#include <span>
#include <vector>

namespace idr::box {

using i128 = __int128;
using ranges::Bounds;

// The fixture of each test of a box, googletest's hook around it: SetUp
// reads the runtime's live cells and TearDown expects them again, and no
// failing input. A box can fail on millions of inputs, and an assertion
// reports each; googletest has none that counts, so `check` counts them and
// reports the first with every operand. `Derived` is the box's own class,
// which names its tests.
template <typename Derived>
class Box : public testing::Test {
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

// A big the test owns, released once when it ends: the runtime's C ABI
// hands out references, and nothing in googletest owns one.
class Owned {
public:
  explicit Owned(idris_rt_big reference) : word(reference) {}
  ~Owned() { idris_rt_big_release(word); }
  Owned(const Owned &) = delete;
  Owned &operator=(const Owned &) = delete;

  idris_rt_big get() const { return word; }
  // Whether the runtime holds it in its word, as the runtime reads one.
  bool small() const { return idris_rt_word_is_small(word); }

private:
  idris_rt_big word;
};

inline Owned big(int64_t x) { return Owned(idris_rt_big_from_int_s(x)); }

inline int sign(i128 v) { return (v > 0) - (v < 0); }

// Whether `v` is inside the small range the runtime declares.
inline bool inside(i128 v) { return v >= IDRIS_RT_SMALL_MIN && v <= IDRIS_RT_SMALL_MAX; }

// Whether the word `r` is `e` in its one representation: inside the small
// range the word of `e`, outside it a cell, read back through the runtime
// (a word that is not small is read as the cell it must then be): compared
// with `e` where an i64 holds it, else by its low 64 bits and its sign.
inline bool represents(idris_rt_big r, i128 e) {
  bool small = idris_rt_word_is_small(r);
  if (inside(e))
    return small && r == big(static_cast<int64_t>(e)).get();
  if (e >= INT64_MIN && e <= INT64_MAX)
    return !small && idris_rt_big_cmp(r, big(static_cast<int64_t>(e)).get()) == 0;
  return !small && static_cast<uint64_t>(idris_rt_big_to_int(r)) == static_cast<uint64_t>(e) &&
         sign(idris_rt_big_cmp(r, big(0).get())) == sign(e);
}

// Whether the runtime's `result`, which the caller hands over, is `e`. It is
// released where it is; a word that is not the one `e` is in may point
// anywhere, and is left.
inline bool is(idris_rt_big result, i128 e) {
  if (!represents(result, e))
    return false;
  idris_rt_big_release(result);
  return true;
}

// Whether the big `r`, which the test owns, is `e`.
inline bool is(const Owned &r, i128 e) { return represents(r.get(), e); }

// B: 0 and every s·2^k + d inside the small range, for s = ±1, k in
// [0, 62] and d in [-2, 2], once each. What a small path, a shift or a word
// op does changes only where an exact result crosses ±2^62, its one
// overflow test, or where two bit lengths (a product's operands', a shift's
// value and amount) add to 62 or 63: every power of two up to the ends of
// the small range with two words either side puts inputs on both sides of
// each boundary for every split of the bits between the two, and meets
// every pattern of high bits, sign and tag there.
inline std::vector<int64_t> boxB() {
  std::vector<int64_t> values{0};
  for (int k = 0; k <= 62; ++k)
    for (i128 s : {1, -1})
      for (i128 d = -2; d <= 2; ++d)
        if (i128 v = s * (i128{1} << k) + d; inside(v))
          values.push_back(static_cast<int64_t>(v));
  std::ranges::sort(values);
  values.erase(std::ranges::unique(values).begin(), values.end());
  return values;
}

// D64: each end of the small range with two neighbours inside it, and 0 with
// two either side, where a rule's or a hook's bounds leave the small range,
// a product leaves i64 or a sign changes.
inline constexpr int64_t d64[] = {
    IDRIS_RT_SMALL_MIN,     IDRIS_RT_SMALL_MIN + 1, IDRIS_RT_SMALL_MIN + 2, -2, -1, 0, 1, 2,
    IDRIS_RT_SMALL_MAX - 2, IDRIS_RT_SMALL_MAX - 1, IDRIS_RT_SMALL_MAX};

// OUT: what a missing bound stands for, below the small range and above it:
// the nearest integer outside it and the end of i64.
inline constexpr int64_t out[] = {IDRIS_RT_SMALL_MIN - 1, INT64_MIN, IDRIS_RT_SMALL_MAX + 1,
                                  INT64_MAX};

// Whether `v` is within `b`: a missing bound holds anything.
inline bool within(i128 v, Bounds b) { return (!b.lo || *b.lo <= v) && (!b.hi || v <= *b.hi); }

// Whether the big `r` is within `b`, by the runtime's order.
inline bool within(const Owned &r, Bounds b) {
  return (!b.lo || idris_rt_big_cmp(r.get(), big(*b.lo).get()) >= 0) &&
         (!b.hi || idris_rt_big_cmp(r.get(), big(*b.hi).get()) <= 0);
}

// Every interval over `points`: each bound one of them inside the small
// range, as a bound is, or none, ordered when both are given.
template <typename Fn>
void eachInterval(std::span<const int64_t> points, Fn fn) {
  std::vector<std::optional<int64_t>> ends{std::nullopt};
  for (int64_t p : points)
    if (inside(p))
      ends.push_back(p);
  for (std::optional<int64_t> lo : ends)
    for (std::optional<int64_t> hi : ends)
      // An empty interval is no interval of a value.
      if (!lo || !hi || *lo <= *hi)
        fn(Bounds{lo, hi});
}

// The members of an interval over `points` an operand may be: the points and
// those of OUT within it, from `least` on, the least the operand may be.
template <typename Fn>
void eachMember(std::span<const int64_t> points, Bounds b, int64_t least, Fn fn) {
  for (int64_t v : points)
    if (v >= least && within(v, b))
      fn(v);
  for (int64_t v : out)
    if (v >= least && within(v, b))
      fn(v);
}

// A member of a range: a value of its width within both its unsigned and its
// signed bounds.
inline bool member(const mlir::ConstantIntRanges &r, const llvm::APInt &v) {
  return r.umin().getBitWidth() == v.getBitWidth() && r.umin().ule(v) && v.ule(r.umax()) &&
         r.smin().sle(v) && v.sle(r.smax());
}

// The range `op`'s hook states of its result on `operands`: MLIR gives it
// only to a callback. Where the hook states none, the range of any value of
// the result's type, which decides and bounds nothing, as no range does for
// idr-narrow.
template <typename OpT>
mlir::ConstantIntRanges inferred(OpT op, llvm::ArrayRef<mlir::ConstantIntRanges> operands) {
  mlir::ConstantIntRanges range =
      mlir::IntegerValueRange::getMaxRange(op->getResult(0)).getValue();
  op.inferResultRanges(operands,
                       [&](mlir::Value, const mlir::ConstantIntRanges &r) { range = r; });
  return range;
}

// Every predicate of the dialect's comparison, from its generated enum.
template <typename Fn>
void eachPredicate(Fn fn) {
  for (uint64_t p = 0; p <= idr::getMaxEnumValForCmpPredicate(); ++p)
    if (std::optional<idr::CmpPredicate> predicate = idr::symbolizeCmpPredicate(p))
      fn(*predicate);
}

// Bounds has no printer, and its namespace, where googletest looks for one,
// is not the boxes'.
inline testing::Message &operator<<(testing::Message &m, Bounds b) {
  return m << "[" << b.lo << ", " << b.hi << "]";
}

} // namespace idr::box

#endif // IDR_TESTING_BOX_H
