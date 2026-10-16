// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// NEEDS-ACCEPTANCE: that the runtime holds a value in a word exactly inside the small range it declares, and that every pair of B through the runtime's add, sub and mul, and every value of B through neg, pred and nat_from_big, is its exact result, a small word exactly inside the small range and a cell outside it; and that cmp orders every pair as its difference does.
// The box of the runtime's tagged small paths of arithmetic: each C entry,
// as the ODS names it for its op, on every small value within 2 of 0 or of
// a power of two, against exact __int128 arithmetic, read back through the
// runtime.

#include "idr/IR/IdrDialect.h"

#include "idris_rt.h"

#include "idr/IR/IdrRuntimeAbi.inc"

#include "gtest/gtest.h"

#include <algorithm>
#include <cstdint>
#include <functional>
#include <vector>

using idr::runtime::Abi;

namespace {

using i128 = __int128;

// The fixture of each test, googletest's hook around it: SetUp reads the
// runtime's live cells and TearDown expects them again, and no failing
// input. A box can fail on millions of inputs, and an assertion reports
// each; googletest has none that counts, so `check` counts them and reports
// the first with every operand.
class Tagged : public testing::Test {
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

private:
  idris_rt_big word;
};

Owned big(int64_t x) { return Owned(idris_rt_big_from_int_s(x)); }

int sign(i128 v) { return (v > 0) - (v < 0); }

// Whether `v` is inside the small range the runtime declares.
bool inside(i128 v) { return v >= IDRIS_RT_SMALL_MIN && v <= IDRIS_RT_SMALL_MAX; }

// Whether the word `r` is `e` in its one representation: inside the small
// range the word of `e`, outside it a cell, read back through the runtime
// (an even word is read as the cell it must then be): compared with `e`
// where an i64 holds it, else by its low 64 bits and its sign.
bool represents(idris_rt_big r, i128 e) {
  bool small = (r & 1) != 0;
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
bool is(idris_rt_big result, i128 e) {
  if (!represents(result, e))
    return false;
  idris_rt_big_release(result);
  return true;
}

// B: 0 and every s·2^k + d inside the small range, for s = ±1, k in
// [0, 62] and d in [-2, 2], once each. A small path changes behaviour only
// where an exact result crosses ±2^62, its one overflow test, or, for a
// product, where the operands' bit lengths add to 62 or 63: every power of
// two up to the ends of the small range with two words either side puts
// pairs on both sides of each boundary for every split of the bits between
// two operands.
std::vector<int64_t> boxB() {
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

// The runtime's `entry` of every pair of B is `exact` of the pair.
template <typename Entry, typename Exact>
void binary(Tagged &box, Entry entry, Exact exact) {
  std::vector<int64_t> values = boxB();
  for (int64_t x : values)
    for (int64_t y : values)
      box.check(is(entry(big(x).get(), big(y).get()), exact(i128{x}, i128{y})),
                [&] { return testing::Message() << "x " << x << ", y " << y; });
}

// The runtime's `entry` of every value of B from `least` on, the least its
// operand may be, is `exact` of it.
template <typename Entry, typename Exact>
void unary(Tagged &box, Entry entry, int64_t least, Exact exact) {
  for (int64_t x : boxB())
    if (x >= least)
      box.check(is(entry(big(x).get()), exact(i128{x})),
                [&] { return testing::Message() << "x " << x; });
}

// The runtime holds a value in a word exactly when it is inside the small
// range it declares, which the narrowing's ranges read.
TEST_F(Tagged, SmallRange) {
  for (int64_t v :
       {IDRIS_RT_SMALL_MIN - 1, IDRIS_RT_SMALL_MIN, IDRIS_RT_SMALL_MAX, IDRIS_RT_SMALL_MAX + 1})
    check(((big(v).get() & 1) != 0) == inside(v),
          [&] { return testing::Message() << "v " << v; });
}

TEST_F(Tagged, Add) { binary(*this, Abi<idr::BigAddOp>::function, std::plus<i128>()); }

TEST_F(Tagged, Sub) { binary(*this, Abi<idr::BigSubOp>::function, std::minus<i128>()); }

TEST_F(Tagged, Mul) { binary(*this, Abi<idr::BigMulOp>::function, std::multiplies<i128>()); }

TEST_F(Tagged, Neg) {
  unary(*this, Abi<idr::BigNegOp>::function, INT64_MIN, std::negate<i128>());
}

// The predecessor of a natural that is not zero.
TEST_F(Tagged, Pred) {
  unary(*this, Abi<idr::BigPredOp>::function, 1, [](i128 x) { return x - 1; });
}

// An Integer as a natural: 0 where it is negative.
TEST_F(Tagged, NatFromBig) {
  unary(*this, Abi<idr::NatFromBigOp>::function, INT64_MIN,
        [](i128 x) { return std::max(x, i128{0}); });
}

// Negative, zero or positive as the first is less than, equal to or greater
// than the second.
TEST_F(Tagged, Cmp) {
  std::vector<int64_t> values = boxB();
  for (int64_t x : values)
    for (int64_t y : values)
      check(sign(Abi<idr::BigCmpOp>::function(big(x).get(), big(y).get())) == sign(i128{x} - y),
            [&] { return testing::Message() << "x " << x << ", y " << y; });
}

} // namespace
