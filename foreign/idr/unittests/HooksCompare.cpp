// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// NEEDS-ACCEPTANCE: that wherever the range hook of big.cmp decides a comparison of two intervals over D64, every member pair the operands may be compares so through the runtime, of Integers and of naturals; and that the range the hook of big.to_int states at 8, 16, 32 and 64 bits holds the runtime's value, wrapped to the width, of every member of every interval over Dw.
// The box of the range hooks of the big ops whose result is an integer:
// each op built in a scratch block, its hook called on every interval as the
// analysis holds one (rangeOf), and the range it states read as the
// ConstantIntRanges it is, against the runtime's value of every member.

#include "Box.h"

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
