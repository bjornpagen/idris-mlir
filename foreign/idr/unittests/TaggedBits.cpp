// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// NEEDS-ACCEPTANCE: that every pair of B through the runtime's and, or and xor is the small word of the two's complement operation on its values, and that every value of B shifted by every amount, left or right through shl and shr either way, is value * 2^n or the floor of value / 2^n, a small word exactly inside the small range.
// The box of the runtime's tagged small paths of the bitwise operations and
// the shifts: each C entry, as the ODS names it for its op, on every small
// value within 2 of 0 or of a power of two and every amount where a shift
// changes behaviour, against the operations of infinite two's complement,
// exact in __int128, read back through the runtime.

#include "idr/IR/IdrDialect.h"

#include "idris_rt.h"

#include "idr/IR/IdrRuntimeAbi.inc"

#include "gtest/gtest.h"

#include <algorithm>
#include <cstdint>
#include <vector>

using idr::runtime::Abi;

namespace {

using i128 = __int128;

// The fixture of each test, googletest's hook around it: SetUp reads the
// runtime's live cells and TearDown expects them again, and no failing
// input. A box can fail on millions of inputs, and an assertion reports
// each; googletest has none that counts, so `check` counts them and reports
// the first with every operand.
class TaggedBits : public testing::Test {
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
// [0, 62] and d in [-2, 2], once each. A shift changes behaviour where the
// value's bit length and the amount add to 62 or 63: every power of two up
// to the ends of the small range with two words either side puts values on
// both sides of that for every amount; the bitwise operations meet every
// pattern of high bits, sign and tag there.
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
