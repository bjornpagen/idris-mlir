// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the word each big op narrows to. The table generated from the
// specification (BigToWord) names a word op per big op; each is built once with arith
// on block arguments and folded by MLIR on every small value within 2 of 0
// or of a power of two, against the runtime's C entry for the big op and
// exact __int128 arithmetic. Then the mask a loop is versioned under, and
// fits32.

#include "idr/Testing/Box.h"

#include "idr/IR/Fold.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Transforms/Narrow.h"

#include "idris_rt.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Block.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"

#include "idr/IR/Generated/BigToWord.h.inc"

#include "gtest/gtest.h"

#include <algorithm>
#include <cstdint>
#include <functional>
#include <optional>
#include <type_traits>
#include <vector>

using idr::BigToWord;
using idr::runtime::Abi;
using llvm::APInt;
using mlir::Attribute;
using mlir::IntegerAttr;
using mlir::Operation;
using mlir::Value;

namespace arith = mlir::arith;

using namespace idr::box;

namespace {

class Words : public Box<Words> {};

// The constant `op` folds to on the constants `operands`, as MLIR folds it:
// an attribute, or one of its operands, whose constant is the one given for
// it; null where it folds to no constant. MLIR folds an op only through
// Operation::fold, whose result may be a value.
Attribute foldedOn(Operation *op, llvm::ArrayRef<Attribute> operands) {
  llvm::SmallVector<mlir::OpFoldResult> results;
  if (mlir::failed(op->fold(operands, results)) || results.empty())
    return {};
  if (auto attribute = llvm::dyn_cast<Attribute>(results.front()))
    return attribute;
  for (mlir::OpOperand &operand : op->getOpOperands())
    if (operand.get() == llvm::cast<Value>(results.front()))
      return operands[operand.getOperandNumber()];
  return {};
}

// The least value the operand of a big op whose word op takes a constant
// may be: a predecessor's is a natural that is not zero.
template <typename OpT>
constexpr int64_t leastOperand = INT64_MIN;
template <>
constexpr int64_t leastOperand<idr::NatPredOp> = 1;

// The meaning of each big op whose word op takes two words: the sum, the
// difference and the product. An op the specification marks later has
// none, and does not compile here until it is given its own.
template <typename OpT>
struct Exact;
template <>
struct Exact<idr::BigAddOp> : std::plus<i128> {};
template <>
struct Exact<idr::BigSubOp> : std::minus<i128> {};
template <>
struct Exact<idr::BigMulOp> : std::multiplies<i128> {};

// The word op BigToWord names for `OpT`, built once on the i64 block
// arguments `a` and `b`, folded on each input of B where every big fits,
// against the runtime's entry for `OpT`. The cases are wordOf's: what the
// word op of each kind computes differs.
template <typename OpT>
void checkWord(Words &box, mlir::OpBuilder &builder, Value a, Value b) {
  using Word = typename BigToWord<OpT>::Op;
  mlir::Location loc = builder.getUnknownLoc();
  std::vector<int64_t> values = boxB();
  auto word = [&](int64_t v) { return builder.getI64IntegerAttr(v); };
  auto operands = [&](int64_t x) {
    return [=] { return testing::Message() << OpT::getOperationName() << ", x " << x; };
  };
  auto pair = [&](int64_t x, int64_t y) {
    return [=] {
      return testing::Message() << OpT::getOperationName() << ", x " << x << ", y " << y;
    };
  };
  if constexpr (std::is_void_v<Word>) {
    // The word is the operand, the op's meaning (the same big under another
    // type), with no runtime function: nothing folds and nothing is called;
    // the case keeps the fold over the list total.
  } else if constexpr (std::is_same_v<Word, arith::CmpIOp>) {
    // A comparison is its predicate on words, signed, whose verdict is the
    // runtime's order under the predicate.
    eachPredicate([&](idr::CmpPredicate predicate) {
      Operation *op = Word::create(builder, loc, idr::layout::signedPredicate(predicate), a, b);
      for (int64_t x : values)
        for (int64_t y : values)
          box.check(foldedOn(op, {word(x), word(y)}) ==
                        idr::fold::ordered(builder.getContext(), static_cast<unsigned>(predicate),
                                           Abi<OpT>::function(big(x).get(), big(y).get())),
                    [&] {
                      return pair(x, y)() << ", " << idr::stringifyCmpPredicate(predicate);
                    });
    });
  } else if constexpr (std::is_same_v<Word, arith::TruncIOp>) {
    // A conversion to a narrower integer truncates the word, which is the
    // runtime's value wrapped to the width; to i64 the word is the value.
    for (unsigned width : {8u, 16u, 32u}) {
      mlir::IntegerType type = builder.getIntegerType(width);
      Operation *op = Word::create(builder, loc, type, a);
      for (int64_t x : values)
        box.check(foldedOn(op, {word(x)}) ==
                      idr::fold::wrapped(type, Abi<OpT>::function(big(x).get())),
                  [&] { return operands(x)() << ", width " << width; });
    }
    for (int64_t x : values)
      box.check(Abi<OpT>::function(big(x).get()) == x, operands(x));
  } else if constexpr (requires { BigToWord<OpT>::constant; }) {
    // The word op of the operand's word and the constant is the runtime's
    // value.
    Operation *op = Word::create(builder, loc, a, b);
    for (int64_t x : values)
      if (x >= leastOperand<OpT>) {
        Owned r(Abi<OpT>::function(big(x).get()));
        auto folded = llvm::dyn_cast_if_present<IntegerAttr>(
            foldedOn(op, {word(x), word(BigToWord<OpT>::constant)}));
        box.check(folded && is(r, folded.getValue().getSExtValue()), operands(x));
      }
    // The larger of a value that is not negative and 0 is the value, whose
    // word the narrowing takes as it is.
    if constexpr (std::is_same_v<Word, arith::MaxSIOp>)
      for (int64_t x : values)
        if (x >= 0)
          box.check(is(Owned(Abi<OpT>::function(big(x).get())), x), operands(x));
  } else {
    // A sum, difference or product of words wraps nowhere the bigs fit: the
    // word is the exact result read signed, and read unsigned where nothing
    // is negative (an attribute holds the bits, so the one comparison states
    // both); and the runtime's value is it.
    Operation *op = Word::create(builder, loc, a, b);
    for (int64_t x : values)
      for (int64_t y : values) {
        i128 e = Exact<OpT>{}(i128{x}, i128{y});
        // The narrowing makes the word op only of bigs that all fit.
        if (!inside(e))
          continue;
        Owned r(Abi<OpT>::function(big(x).get(), big(y).get()));
        box.check(foldedOn(op, {word(x), word(y)}) == word(static_cast<int64_t>(e)) && is(r, e),
                  pair(x, y));
      }
  }
}

// Every big op the specification marks, in one fold over the generated
// list: an op marked later is checked here or fails to compile.
template <typename... Ops>
void checkEachWord(Words &box, mlir::OpBuilder &builder, Value a, Value b) {
  (checkWord<Ops>(box, builder, a, b), ...);
}

TEST_F(Words, EachBigOpIsItsWordOp) {
  mlir::MLIRContext context;
  context.loadDialect<arith::ArithDialect>();
  idr::box::Scratch scratch(context);
  mlir::Block &block = scratch.block();
  mlir::Type i64 = mlir::IntegerType::get(&context, 64);
  Value a = block.addArgument(i64, mlir::UnknownLoc::get(&context));
  Value b = block.addArgument(i64, mlir::UnknownLoc::get(&context));
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  checkEachWord<
#define GET_BIG_TO_WORD_LIST
#include "idr/IR/Generated/BigToWord.h.inc"
      >(*this, builder, a, b);
}

// The mask a loop is versioned under: a natural not above the small range's
// top compares so with it, and its word masked by the top is the runtime's
// word of it; a natural above the top compares above it.
TEST_F(Words, Mask) {
  mlir::MLIRContext context;
  context.loadDialect<arith::ArithDialect>();
  idr::box::Scratch scratch(context);
  mlir::Block &block = scratch.block();
  mlir::Type i64 = mlir::IntegerType::get(&context, 64);
  Value a = block.addArgument(i64, mlir::UnknownLoc::get(&context));
  Value b = block.addArgument(i64, mlir::UnknownLoc::get(&context));
  mlir::OpBuilder builder = mlir::OpBuilder::atBlockEnd(&block);
  Operation *mask = arith::AndIOp::create(builder, builder.getUnknownLoc(), a, b);
  Owned top = big(IDRIS_RT_SMALL_MAX);
  for (int64_t x : boxB())
    if (x >= 0) {
      Owned n = big(x);
      check(Abi<idr::BigCmpOp>::function(n.get(), top.get()) <= 0 &&
                foldedOn(mask, {builder.getI64IntegerAttr(x),
                                builder.getI64IntegerAttr(IDRIS_RT_SMALL_MAX)}) ==
                    builder.getI64IntegerAttr(Abi<idr::BigToIntOp>::function(n.get())),
            [&] { return testing::Message() << "x " << x; });
    }
  // One past the top, the top of i64 and 2^64.
  Owned above[] = {
      Owned(idris_rt_big_from_int_u(uint64_t{IDRIS_RT_SMALL_MAX} + 1)),
      Owned(idris_rt_big_from_int_u(INT64_MAX)),
      Owned(Abi<idr::BigShlOp>::function(big(1).get(), big(64).get())),
  };
  for (const Owned &n : above)
    check(Abi<idr::BigCmpOp>::function(n.get(), top.get()) > 0,
          [&] { return testing::Message() << "natural " << idris_rt_big_to_double(n.get()); });
}

// A 64-bit range fits a signed 32-bit word exactly when both its signed
// bounds are within i32; a range of 32 bits or fewer always does.
TEST_F(Words, Fits32) {
  // W32: each end of i32 and 0, with two either side, and the ends of i64.
  std::vector<int64_t> w32{INT64_MIN, INT64_MAX};
  for (int64_t d = -2; d <= 2; ++d)
    w32.insert(w32.end(), {int64_t{INT32_MIN} + d, d, int64_t{INT32_MAX} + d});
  for (int64_t lo : w32)
    for (int64_t hi : w32)
      if (lo <= hi)
        check(idr::narrow::fits32(mlir::ConstantIntRanges::fromSigned(
                  APInt(64, static_cast<uint64_t>(lo), /*isSigned=*/true),
                  APInt(64, static_cast<uint64_t>(hi), /*isSigned=*/true))) ==
                  (lo >= INT32_MIN && hi <= INT32_MAX),
              [&] { return testing::Message() << "lo " << lo << ", hi " << hi; });
  for (unsigned width : {8u, 16u, 32u}) {
    APInt ends[] = {APInt::getSignedMinValue(width), APInt::getZero(width),
                    APInt::getSignedMaxValue(width)};
    for (const APInt &lo : ends)
      for (const APInt &hi : ends)
        if (lo.sle(hi))
          check(idr::narrow::fits32(mlir::ConstantIntRanges::fromSigned(lo, hi)),
                [&] { return testing::Message() << "lo " << lo << ", hi " << hi; });
  }
}

} // namespace
