// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// NEEDS-ACCEPTANCE: that wherever the range hook of big.cmp decides a comparison of two intervals over D64, every member pair the operands may be compares so through the runtime, of Integers and of naturals; and that the range the hook of big.to_int states at 8, 16, 32 and 64 bits holds the runtime's value, wrapped to the width, of every member of every interval over Dw.
// The box of the range hooks of the big ops whose result is an integer:
// each op built in a scratch block, its hook called on every interval as the
// analysis holds one (rangeOf), and the range it states read as the
// ConstantIntRanges it is, against the runtime's value of every member.

#include "idr/IR/Fold.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"

#include "idris_rt.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Support/DebugStringHelper.h"

#include "gtest/gtest.h"

#include <cstdint>
#include <iterator>
#include <optional>
#include <span>
#include <utility>
#include <vector>

using idr::ranges::Bounds;
using idr::runtime::Abi;
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
class HooksCompare : public testing::Test {
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

// D64: each end of the small range with two neighbours inside it, and 0 with
// two either side, where a hook's bounds leave the small range or change
// sign.
constexpr int64_t d64[] = {
    IDRIS_RT_SMALL_MIN,     IDRIS_RT_SMALL_MIN + 1, IDRIS_RT_SMALL_MIN + 2, -2, -1, 0, 1, 2,
    IDRIS_RT_SMALL_MAX - 2, IDRIS_RT_SMALL_MAX - 1, IDRIS_RT_SMALL_MAX};

// OUT: what a missing bound stands for, below the small range and above it:
// the nearest integer outside it and the end of i64.
constexpr int64_t out[] = {IDRIS_RT_SMALL_MIN - 1, INT64_MIN, IDRIS_RT_SMALL_MAX + 1,
                           INT64_MAX};

// Dw, for big.to_int at `width` bits: D64 and, within 2 of each, where a
// value stops fitting the width signed (±2^(w-1)) or unsigned (2^w), as an
// i64 holds them: the two cases of the hook.
std::vector<int64_t> dw(unsigned width) {
  std::vector<int64_t> points(std::begin(d64), std::end(d64));
  for (i128 edge : {-(i128{1} << (width - 1)), i128{1} << (width - 1), i128{1} << width})
    for (i128 d = -2; d <= 2; ++d)
      if (i128 v = edge + d; v >= INT64_MIN && v <= INT64_MAX)
        points.push_back(static_cast<int64_t>(v));
  return points;
}

// Whether `v` is within `b`: a missing bound holds anything.
bool within(int64_t v, Bounds b) { return (!b.lo || *b.lo <= v) && (!b.hi || v <= *b.hi); }

// A member of a range: a value of its width within both its unsigned and its
// signed bounds.
bool member(const ConstantIntRanges &r, const APInt &v) {
  return r.umin().getBitWidth() == v.getBitWidth() && r.umin().ule(v) && v.ule(r.umax()) &&
         r.smin().sle(v) && v.sle(r.smax());
}

// Bounds has no printer, and its namespace, where googletest looks for one,
// is not this unit's.
testing::Message &operator<<(testing::Message &m, Bounds b) {
  return m << "[" << b.lo << ", " << b.hi << "]";
}

// Every interval over `points`: each bound one inside the small range, as a
// bound is, or none, ordered when both are given.
template <typename Fn>
void eachInterval(std::span<const int64_t> points, Fn fn) {
  std::vector<std::optional<int64_t>> ends{std::nullopt};
  for (int64_t p : points)
    if (p >= IDRIS_RT_SMALL_MIN && p <= IDRIS_RT_SMALL_MAX)
      ends.push_back(p);
  for (std::optional<int64_t> lo : ends)
    for (std::optional<int64_t> hi : ends)
      // An empty interval is no interval of a value.
      if (!lo || !hi || *lo <= *hi)
        fn(Bounds{lo, hi});
}

// The members of an interval over `points` an operand may be: the points and
// those of OUT within it, from `least` on.
template <typename Fn>
void eachMember(std::span<const int64_t> points, Bounds b, int64_t least, Fn fn) {
  for (int64_t v : points)
    if (v >= least && within(v, b))
      fn(v);
  for (int64_t v : out)
    if (v >= least && within(v, b))
      fn(v);
}

// The range `op`'s hook states of its result on `operands`: MLIR gives it
// only to a callback. Where the hook states none, the range of any value of
// the result's type, which decides and bounds nothing.
template <typename OpT>
ConstantIntRanges inferred(OpT op, llvm::ArrayRef<ConstantIntRanges> operands) {
  ConstantIntRanges range = mlir::IntegerValueRange::getMaxRange(op->getResult(0)).getValue();
  op.inferResultRanges(operands, [&](mlir::Value, const ConstantIntRanges &r) { range = r; });
  return range;
}

// Every predicate of the dialect's comparison, from its generated enum.
template <typename Fn>
void eachPredicate(Fn fn) {
  for (uint64_t p = 0; p <= idr::getMaxEnumValForCmpPredicate(); ++p)
    if (std::optional<idr::CmpPredicate> predicate = idr::symbolizeCmpPredicate(p))
      fn(*predicate);
}

TEST_F(HooksCompare, Cmp) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::arith::ArithDialect>();
  mlir::Block block;
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  mlir::Location loc = builder.getUnknownLoc();
  // Two Integers, of any member, and two naturals, of the members not
  // negative.
  std::pair<mlir::Type, int64_t> operands[] = {{idr::BigType::get(&context), INT64_MIN},
                                               {idr::NatType::get(&context), 0}};
  for (auto [type, least] : operands) {
    mlir::Value lhs = block.addArgument(type, loc), rhs = block.addArgument(type, loc);
    eachPredicate([&](idr::CmpPredicate predicate) {
      auto op = idr::BigCmpOp::create(builder, loc, predicate, lhs, rhs);
      eachInterval(d64, [&](Bounds a) {
        eachInterval(d64, [&](Bounds b) {
          std::optional<APInt> decided =
              inferred(op, {ranges::rangeOf(a), ranges::rangeOf(b)}).getConstantValue();
          // A comparison the ranges leave undecided states nothing.
          if (!decided)
            return;
          mlir::Attribute verdict = mlir::BoolAttr::get(&context, decided->getBoolValue());
          eachMember(d64, a, least, [&](int64_t x) {
            eachMember(d64, b, least, [&](int64_t y) {
              int32_t order = Abi<idr::BigCmpOp>::function(big(x).get(), big(y).get());
              check(idr::fold::compared(&context, predicate, order) == verdict, [&] {
                return testing::Message() << mlir::debugString(type) << ", "
                                          << idr::stringifyCmpPredicate(predicate) << ", a " << a
                                          << ", b " << b << ", x " << x << ", y " << y;
              });
            });
          });
        });
      });
    });
  }
}

TEST_F(HooksCompare, ToInt) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::arith::ArithDialect>();
  mlir::Block block;
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  mlir::Location loc = builder.getUnknownLoc();
  // An Integer, of any member, and a natural, of the members not negative.
  std::pair<mlir::Type, int64_t> operands[] = {{idr::BigType::get(&context), INT64_MIN},
                                               {idr::NatType::get(&context), 0}};
  for (auto [type, least] : operands)
    for (unsigned width : {8u, 16u, 32u, 64u}) {
      mlir::IntegerType result = builder.getIntegerType(width);
      auto op = idr::BigToIntOp::create(builder, loc, result, block.addArgument(type, loc));
      std::vector<int64_t> points = dw(width);
      eachInterval(points, [&](Bounds b) {
        ConstantIntRanges range = inferred(op, {ranges::rangeOf(b)});
        eachMember(points, b, least, [&](int64_t x) {
          auto value = llvm::cast<mlir::IntegerAttr>(
              idr::fold::wrapped(result, Abi<idr::BigToIntOp>::function(big(x).get())));
          check(member(range, value.getValue()), [&] {
            return testing::Message() << mlir::debugString(type) << ", width " << width
                                      << ", b " << b << ", x " << x << ": " << range;
          });
        });
      });
    }
}

} // namespace
