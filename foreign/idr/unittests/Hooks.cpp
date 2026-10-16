// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// NEEDS-ACCEPTANCE: that the bounds the range hooks of pred, nat_from_big and nat.to_big state on every interval over D64 hold the runtime's value of every member their operand may be.
// The box of the range hooks of the big ops of one operand: each op built
// in a scratch block, its hook called on every interval over D64 as the
// analysis holds one (rangeOf), and the range it states read as idr-narrow
// reads it (boundsOf), against the runtime's value of every member.

#include "idr/IR/Fold.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"

#include "idris_rt.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"

#include "gtest/gtest.h"

#include <cstdint>
#include <iterator>
#include <optional>
#include <vector>

using idr::ranges::Bounds;
using idr::runtime::Abi;
using mlir::ConstantIntRanges;

namespace ranges = idr::ranges;

namespace {

// The fixture of each test, googletest's hook around it: SetUp reads the
// runtime's live cells and TearDown expects them again, and no failing
// input. A box can fail on millions of inputs, and an assertion reports
// each; googletest has none that counts, so `check` counts them and reports
// the first with every operand.
class Hooks : public testing::Test {
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

// Whether `v` is within `b`: a missing bound holds anything.
bool within(int64_t v, Bounds b) { return (!b.lo || *b.lo <= v) && (!b.hi || v <= *b.hi); }

// Whether the big `r` is within `b`, by the runtime's order.
bool within(const Owned &r, Bounds b) {
  return (!b.lo || idris_rt_big_cmp(r.get(), big(*b.lo).get()) >= 0) &&
         (!b.hi || idris_rt_big_cmp(r.get(), big(*b.hi).get()) <= 0);
}

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

// The members of an interval an operand may be: the points of D64 and of
// OUT within it, from `least` on.
template <typename Fn>
void eachMember(Bounds b, int64_t least, Fn fn) {
  for (int64_t v : d64)
    if (v >= least && within(v, b))
      fn(v);
  for (int64_t v : out)
    if (v >= least && within(v, b))
      fn(v);
}

// The range `op`'s hook states of its result on `operands`: MLIR gives it
// only to a callback. Where the hook states none, the range of any value of
// the result's type, which bounds nothing, as no range does for idr-narrow.
template <typename OpT>
ConstantIntRanges inferred(OpT op, llvm::ArrayRef<ConstantIntRanges> operands) {
  ConstantIntRanges range = mlir::IntegerValueRange::getMaxRange(op->getResult(0)).getValue();
  op.inferResultRanges(operands, [&](mlir::Value, const ConstantIntRanges &r) { range = r; });
  return range;
}

// The hook of `op`, of one operand, on every interval over D64: each member
// from `least` on, the least the operand may be, has the value `value`
// gives within the bounds the hook states.
template <typename OpT, typename ValueFn>
void checkUnary(Hooks &box, OpT op, int64_t least, ValueFn value) {
  eachInterval([&](Bounds b) {
    Bounds result = ranges::boundsOf(inferred(op, {ranges::rangeOf(b)}));
    eachMember(b, least, [&](int64_t x) {
      box.check(within(value(x), result), [&] {
        return testing::Message() << "operand " << b << ", x " << x << ": " << result;
      });
    });
  });
}

TEST_F(Hooks, Pred) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::arith::ArithDialect>();
  mlir::Block block;
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  mlir::Location loc = builder.getUnknownLoc();
  mlir::Type nat = idr::NatType::get(&context);
  auto op = idr::BigPredOp::create(builder, loc, nat, block.addArgument(nat, loc));
  // The operand is a natural that is not zero.
  checkUnary(*this, op, 1,
             [](int64_t x) { return Owned(Abi<idr::BigPredOp>::function(big(x).get())); });
}

TEST_F(Hooks, NatFromBig) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::arith::ArithDialect>();
  mlir::Block block;
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  mlir::Location loc = builder.getUnknownLoc();
  auto op = idr::NatFromBigOp::create(builder, loc, idr::NatType::get(&context),
                                      block.addArgument(idr::BigType::get(&context), loc));
  // The operand is any Integer.
  checkUnary(*this, op, INT64_MIN,
             [](int64_t x) { return Owned(Abi<idr::NatFromBigOp>::function(big(x).get())); });
}

TEST_F(Hooks, NatToBig) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::arith::ArithDialect>();
  mlir::Block block;
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  mlir::Location loc = builder.getUnknownLoc();
  auto op = idr::NatToBigOp::create(builder, loc, idr::BigType::get(&context),
                                    block.addArgument(idr::NatType::get(&context), loc));
  // The operand is a natural, and the result the same big under another
  // type, with no runtime function.
  checkUnary(*this, op, 0, [](int64_t x) { return big(x); });
}

} // namespace
