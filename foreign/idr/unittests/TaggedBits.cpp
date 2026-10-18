// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the runtime's tagged small paths of the bitwise operations and
// the shifts: each C entry, as the ODS names it for its op, on every small
// value within 2 of 0 or of a power of two and every amount where a shift
// changes behaviour, against the operations of infinite two's complement,
// exact in __int128, read back through the runtime.

#include "idr/Testing/Box.h"

#include "idr/IR/IdrDialect.h"

#include "idris_rt.h"

#include "idr/IR/IdrRuntimeAbi.inc"

#include "gtest/gtest.h"

#include <cstdint>
#include <vector>

using idr::runtime::Abi;
using namespace idr::box;

namespace {

class TaggedBits : public Box<TaggedBits> {};

// The amounts a shift moves left by: every one up to 64. 63 places is past
// the small path's last, and a small value times 2^64 still fits __int128.
std::vector<int64_t> leftAmounts() {
  std::vector<int64_t> amounts;
  for (int64_t n = 0; n <= 64; ++n)
    amounts.push_back(n);
  return amounts;
}

// The amounts a shift moves right by: every one up to 130, since from 63
// places only the sign is left and 130 is past twice a word, and every
// 2^k and 2^k + 1 for k in [8, 61] with the small range's top, the amounts
// beyond that an operand may hold.
std::vector<int64_t> rightAmounts() {
  std::vector<int64_t> amounts;
  for (int64_t n = 0; n <= 130; ++n)
    amounts.push_back(n);
  for (int k = 8; k <= 61; ++k)
    amounts.insert(amounts.end(), {int64_t{1} << k, (int64_t{1} << k) + 1});
  amounts.push_back(IDRIS_RT_SMALL_MAX);
  return amounts;
}

// The runtime's `entry` of every pair of B is the small word of `exact`, the
// operation on the values: a bitwise operation of small values is small.
template <typename Entry, typename Exact>
void bitwise(TaggedBits &box, Entry entry, Exact exact) {
  std::vector<int64_t> values = boxB();
  for (int64_t x : values)
    for (int64_t y : values)
      box.check(is(entry(big(x).get(), big(y).get()), exact(x, y)),
                [&] { return testing::Message() << "x " << x << ", y " << y; });
}

// The runtime's `entry` of every value of B and `direction` times each of
// `amounts`, the amount it moves by that way, is `exact` of the value and
// the amount.
template <typename Entry, typename Exact>
void shifts(TaggedBits &box, Entry entry, const std::vector<int64_t> &amounts,
            int64_t direction, Exact exact) {
  for (int64_t x : boxB())
    for (int64_t n : amounts)
      box.check(is(entry(big(x).get(), big(direction * n).get()), exact(i128{x}, n)),
                [&] { return testing::Message() << "x " << x << ", amount " << direction * n; });
}

// Left by n: value * 2^n.
i128 left(i128 x, int64_t n) { return x * (i128{1} << n); }

// Right by n: the floor of value / 2^n, which C++'s >> is on an i64; from
// 63 places on only the sign is left.
i128 right(i128 x, int64_t n) {
  return n <= 62 ? static_cast<int64_t>(x) >> n : (x < 0 ? -1 : 0);
}

TEST_F(TaggedBits, And) {
  bitwise(*this, Abi<idr::BigAndOp>::function, [](int64_t x, int64_t y) { return x & y; });
}

TEST_F(TaggedBits, Or) {
  bitwise(*this, Abi<idr::BigOrOp>::function, [](int64_t x, int64_t y) { return x | y; });
}

TEST_F(TaggedBits, Xor) {
  bitwise(*this, Abi<idr::BigXorOp>::function, [](int64_t x, int64_t y) { return x ^ y; });
}

// shl by an amount not negative moves left, and shr by one not positive.
TEST_F(TaggedBits, ShlLeft) { shifts(*this, Abi<idr::BigShlOp>::function, leftAmounts(), 1, left); }

TEST_F(TaggedBits, ShrLeft) {
  shifts(*this, Abi<idr::BigShrOp>::function, leftAmounts(), -1, left);
}

// shr by an amount not negative moves right, and shl by one not positive.
TEST_F(TaggedBits, ShrRight) {
  shifts(*this, Abi<idr::BigShrOp>::function, rightAmounts(), 1, right);
}

TEST_F(TaggedBits, ShlRight) {
  shifts(*this, Abi<idr::BigShlOp>::function, rightAmounts(), -1, right);
}

} // namespace
