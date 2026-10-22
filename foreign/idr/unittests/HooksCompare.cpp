// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the range hooks of the big ops whose result is an integer:
// each op built in a scratch block, its hook called on every interval as the
// analysis holds one (rangeOf), and the range it states read as the
// ConstantIntRanges it is, against the runtime's value of every member;
// then against a runtime with a fault planted in the op, which the check
// must catch, so that a hook that decides or bounds nothing would not pass.

#include "idr/Testing/Box.h"

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

using idr::runtime::Abi;
using llvm::APInt;
using mlir::ConstantIntRanges;

namespace ranges = idr::ranges;

using namespace idr::box;

namespace {

class HooksCompare : public Box<HooksCompare> {};

// A judge for a mutant, which counts the cases that fail and reports none.
struct Mutant {
  unsigned failures = 0;
  template <typename Operands>
  void check(bool holds, Operands) {
    failures += !holds;
  }
};

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

// big.cmp's hook, where it decides a comparison, against the order `order`
// gives every pair of members.
template <typename Judge, typename Order>
void checkCmp(Judge &box, Order order) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::arith::ArithDialect>();
  idr::box::Scratch scratch(context);
  mlir::Block &block = scratch.block();
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  mlir::Location loc = builder.getUnknownLoc();
  // Two Integers, of any member, and two naturals, of the members not
  // negative.
  std::pair<mlir::Type, int64_t> operands[] = {{idr::BigType::get(&context), INT64_MIN},
                                               {idr::NatType::get(&context), 0}};
  for (auto [type, least] : operands) {
    mlir::Value lhs = block.addArgument(type, loc), rhs = block.addArgument(type, loc);
    eachPredicate([&](idr::CmpPredicate predicate) {
      auto op = idr::BigCmpOp::create(builder, loc, lhs, rhs, predicate);
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
              mlir::Attribute folded = idr::fold::ordered(
                  &context, static_cast<unsigned>(predicate), order(x, y));
              box.check(folded == verdict, [&] {
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

TEST_F(HooksCompare, Cmp) {
  checkCmp(*this, [](int64_t x, int64_t y) {
    return Abi<idr::BigCmpOp>::function(big(x).get(), big(y).get());
  });
  // A comparison that orders its operands the other way.
  Mutant mutant;
  checkCmp(mutant, [](int64_t x, int64_t y) {
    return Abi<idr::BigCmpOp>::function(big(y).get(), big(x).get());
  });
  EXPECT_GT(mutant.failures, 0u);
}

// big.to_int's hook at each width, on every interval over Dw, against the
// word `value` gives every member.
template <typename Judge, typename Value>
void checkToInt(Judge &box, Value value) {
  mlir::MLIRContext context;
  context.loadDialect<idr::IdrDialect, mlir::arith::ArithDialect>();
  idr::box::Scratch scratch(context);
  mlir::Block &block = scratch.block();
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
          auto word = llvm::cast<mlir::IntegerAttr>(idr::fold::wrapped(result, value(x)));
          box.check(member(range, word.getValue()), [&] {
            return testing::Message() << mlir::debugString(type) << ", width " << width
                                      << ", b " << b << ", x " << x << ": " << range;
          });
        });
      });
    }
}

TEST_F(HooksCompare, ToInt) {
  checkToInt(*this, [](int64_t x) { return Abi<idr::BigToIntOp>::function(big(x).get()); });
  // A conversion whose word is one more, wrapping.
  Mutant mutant;
  checkToInt(mutant, [](int64_t x) {
    auto word = static_cast<uint64_t>(Abi<idr::BigToIntOp>::function(big(x).get()));
    return static_cast<int64_t>(word + 1);
  });
  EXPECT_GT(mutant.failures, 0u);
}

} // namespace
