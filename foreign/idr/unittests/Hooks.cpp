// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the range hooks of the big ops of one operand: each op built
// in a scratch block, its hook called on every interval over D64 as the
// analysis holds one (rangeOf), and the range it states read as the
// narrowing reads it (boundsOf), against the runtime's value of every
// member; then against a runtime with a fault planted in the op, which the
// check must catch, so that a hook stating no bound would not pass.

#include "idr/Testing/Box.h"

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

using idr::runtime::Abi;

namespace ranges = idr::ranges;

using namespace idr::box;

namespace {

class Hooks : public Box<Hooks> {};

// A judge for a mutant, which counts the cases that fail and reports none.
struct Mutant {
  unsigned failures = 0;
  template <typename Operands>
  void check(bool holds, Operands) {
    failures += !holds;
  }
};

// The hook of `op`, of one operand, on every interval over D64: each member
// from `least` on, the least the operand may be, has the value `value`
// gives within the bounds the hook states.
template <typename Judge, typename OpT, typename ValueFn>
void checkUnary(Judge &box, OpT op, int64_t least, ValueFn value) {
  eachInterval(d64, [&](Bounds b) {
    Bounds result = ranges::boundsOf(inferred(op, {ranges::rangeOf(b)}));
    eachMember(d64, b, least, [&](int64_t x) {
      box.check(within(value(x), result), [&] {
        return testing::Message() << "operand " << b << ", x " << x << ": " << result;
      });
    });
  });
}

TEST_F(Hooks, Pred) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::arith::ArithDialect>();
  idr::box::Scratch scratch(context);
  mlir::Block &block = scratch.block();
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  mlir::Location loc = builder.getUnknownLoc();
  mlir::Type nat = idr::NatType::get(&context);
  auto op = idr::BigPredOp::create(builder, loc, nat, block.addArgument(nat, loc));
  // The operand is a natural that is not zero.
  checkUnary(*this, op, 1,
             [](int64_t x) { return Owned(Abi<idr::BigPredOp>::function(big(x).get())); });
  // A predecessor that gives its operand back.
  Mutant mutant;
  checkUnary(mutant, op, 1, [](int64_t x) { return big(x); });
  EXPECT_GT(mutant.failures, 0u);
}

TEST_F(Hooks, NatFromBig) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::arith::ArithDialect>();
  idr::box::Scratch scratch(context);
  mlir::Block &block = scratch.block();
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  mlir::Location loc = builder.getUnknownLoc();
  auto op = idr::NatFromBigOp::create(builder, loc, idr::NatType::get(&context),
                                      block.addArgument(idr::BigType::get(&context), loc));
  // The operand is any Integer.
  checkUnary(*this, op, INT64_MIN,
             [](int64_t x) { return Owned(Abi<idr::NatFromBigOp>::function(big(x).get())); });
  // A conversion that keeps a negative operand.
  Mutant mutant;
  checkUnary(mutant, op, INT64_MIN, [](int64_t x) { return big(x); });
  EXPECT_GT(mutant.failures, 0u);
}

TEST_F(Hooks, NatToBig) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::arith::ArithDialect>();
  idr::box::Scratch scratch(context);
  mlir::Block &block = scratch.block();
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  mlir::Location loc = builder.getUnknownLoc();
  auto op = idr::NatToBigOp::create(builder, loc, idr::BigType::get(&context),
                                    block.addArgument(idr::NatType::get(&context), loc));
  // The operand is a natural, and the result the same big under another
  // type, with no runtime function.
  checkUnary(*this, op, 0, [](int64_t x) { return big(x); });
  // A conversion that adds one.
  Mutant mutant;
  checkUnary(mutant, op, 0, [](int64_t x) { return big(x < INT64_MAX ? x + 1 : x); });
  EXPECT_GT(mutant.failures, 0u);
}

} // namespace
