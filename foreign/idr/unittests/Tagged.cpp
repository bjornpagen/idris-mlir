// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// NEEDS-ACCEPTANCE: that the runtime holds a value in a word exactly inside the small range it declares, and that every pair of B through the runtime's add, sub and mul, and every value of B through neg, pred and nat_from_big, is its exact result, a small word exactly inside the small range and a cell outside it; and that cmp orders every pair as its difference does.
// The box of the runtime's tagged small paths of arithmetic: each C entry,
// as the ODS names it for its op, on every small value within 2 of 0 or of
// a power of two, against exact __int128 arithmetic, read back through the
// runtime.

#include "idr/Testing/Box.h"

#include "idr/IR/IdrDialect.h"

#include "idris_rt.h"

#include "idr/IR/IdrRuntimeAbi.inc"

#include "gtest/gtest.h"

#include <algorithm>
#include <cstdint>
#include <functional>
#include <vector>

using idr::runtime::Abi;
using namespace idr::box;

namespace {

class Tagged : public Box<Tagged> {};

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
    check(big(v).small() == inside(v),
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
