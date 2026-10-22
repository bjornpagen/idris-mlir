// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The counting ops, lowered: each a primitive by the time it gets here,
// since counting decided everything above the lowering. A count is kept by
// the entry of each word's kind, which its type gives (a cell, a cell or
// null, a cell or a small value, any of them), so no entry tests what the
// type rules out. A value its type proves unshared meets no count and no
// test; the one test of sharing left is a match on uniqueness, which
// counting made only where the type proves nothing, and which lowers to a
// branch on the count being 1. A share, of a value or of a token widened at
// a rejoin, is its operand's words: the one pattern of the ops whose result
// carries their operand (Lower.cpp) lowers it, as the ops with no runtime
// form of their own, a buffer counting takes over and a value handed to the
// memory that stores it.

#include "Lower.h"

#include "idr/IR/Grades.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/SCF/IR/SCF.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The fields of a value refined to one constructor laid out in a cell, at
// `cell`, read out with the references the cell held: a data cell's fields
// stay until its memory is reused, a memo cell's change when it is forced.
SmallVector<SmallVector<Value>> fieldsAt(OpBuilder &b, Location loc, const Runtime &runtime,
                                         const Layouts &layouts, Value cell, DataType data) {
  const layout::Cell &layout = layouts.cells(data).cell(tagOf(data));
  Contents stays = data.memo() ? Contents::MayChange : Contents::Stays;
  return llvm::map_to_vector(layout.fields, [&](ArrayRef<layout::Slot> slots) {
    return runtime.load(b, loc, cell, cellAlignment(), slots, stays);
  });
}

DataType refinedOf(Value value) { return cast<DataType>(unrestricted(value.getType())); }

// One more reference to each counted word of the value, which is then the
// result's.
struct LowerDup : IdrPattern<CountDupOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CountDupOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    ValueRange value = adaptor.getValue();
    runtime.inc(rewriter, op.getLoc(), layouts.components(op.getValue().getType()), value);
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(value)});
    return success();
  }
};

// One reference less to each counted word of the value, a cell freed at 0.
struct LowerDrop : IdrPattern<CountDropOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CountDropOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    runtime.dec(rewriter, op.getLoc(), layouts.components(op.getValue().getType()),
                adaptor.getValue());
    rewriter.eraseOp(op);
    return success();
  }
};

// A take of a value its type proves holds its cell alone: the token is the
// cell, the fields its slots, with no test. A take of any other value is
// counting's expansion's to make a match on uniqueness, so it never reaches
// here.
struct LowerTake : IdrPattern<CountTakeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CountTakeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    if (!claims(op.getValue().getType(), Unique::Self))
      return rewriter.notifyMatchFailure(op, "a take of a value its type proves nothing of");
    Value cell = adaptor.getValue().front();
    SmallVector<SmallVector<Value>> out{{cell}};
    llvm::append_range(out, fieldsAt(rewriter, op.getLoc(), runtime, layouts, cell,
                                     refinedOf(op.getValue())));
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }
};

// A take whose token one construction recycles on every path: the fields
// read out; held alone, the cell made the new constructor's (its header
// kept where the constructor is the same); shared, each field given a
// reference of its own, the value's reference given up, and a fresh cell.
// The test runs only where the type proves nothing of the sharing.
struct LowerTakeInto : IdrPattern<CountTakeIntoOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CountTakeIntoOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value cell = adaptor.getValue().front();
    DataType from = refinedOf(op.getValue());
    auto into = cast<CellType>(op.getCell().getType());
    const layout::Cell &target = cellLayoutOf(layouts, into);
    SmallVector<SmallVector<Value>> fields = fieldsAt(rewriter, loc, runtime, layouts, cell, from);
    auto reuse = [&](OpBuilder &b) {
      if (Type(from) != into.getValue())
        runtime.storeInfoAndWords(b, loc, cell, target);
    };
    Value made;
    if (claims(op.getValue().getType(), Unique::Self)) {
      reuse(rewriter);
      made = cell;
    } else {
      Type ptr = cell.getType();
      auto alone = scf::IfOp::create(rewriter, loc, TypeRange{ptr},
                                     runtime.isUnique(rewriter, loc, cell), /*withElseRegion=*/true);
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(alone.thenBlock());
      reuse(rewriter);
      scf::YieldOp::create(rewriter, loc, cell);
      rewriter.setInsertionPointToStart(alone.elseBlock());
      const layout::Cell &source = layouts.cells(from).cell(tagOf(from));
      for (auto [slots, values] : llvm::zip_equal(source.fields, fields)) {
        SmallVector<layout::Component> components(slots.begin(), slots.end());
        runtime.inc(rewriter, loc, components, values);
      }
      runtime.dec(rewriter, loc, layout::Word::Cell, cell);
      scf::YieldOp::create(rewriter, loc, runtime.allocate(rewriter, loc, target));
      made = alone.getResult(0);
    }
    SmallVector<SmallVector<Value>> out{{runtime.launder(rewriter, loc, made)}};
    llvm::append_range(out, fields);
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }
};

// The one run-time test of sharing, where the type proves nothing of it:
// a branch on the count being 1. Held alone, the unique region gets the
// cell as its token and the fields moved out; shared, the shared region
// gets the value itself. Each region's yield gives the op's results.
struct LowerMatchUnique : IdrPattern<CountMatchUniqueOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(CountMatchUniqueOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    FailureOr<SmallVector<SmallVector<Type>>> converted =
        convertedResults(op, *getTypeConverter());
    if (failed(converted))
      return rewriter.notifyMatchFailure(op, "a result's type does not convert");
    SmallVector<Type> flat;
    for (ArrayRef<Type> components : *converted)
      llvm::append_range(flat, components);
    SmallVector<Value> value(adaptor.getValue());
    Value cell = value.front();
    // The fields are read before the branch: the shared path does not need
    // them, and reading a live cell's slots is harmless where it runs.
    SmallVector<SmallVector<Value>> uniqueArgs{{cell}};
    llvm::append_range(uniqueArgs,
                       fieldsAt(rewriter, loc, runtime, layouts, cell, refinedOf(op.getValue())));
    auto alone = scf::IfOp::create(rewriter, loc, flat, runtime.isUnique(rewriter, loc, cell),
                                   /*addThenBlock=*/false, /*addElseBlock=*/false);
    moveRegion(rewriter, *getTypeConverter(), op.getUnique(), uniqueArgs, alone.getThenRegion());
    moveRegion(rewriter, *getTypeConverter(), op.getShared(), {value}, alone.getElseRegion());
    rewriter.replaceOpWithMultiple(op, groupResults(alone.getResults(), *converted));
    return success();
  }
};

// Frees the emptied cell a token holds: with no test where its grade says
// it holds one, and testing only for null where it may not, the copy
// budget's fallback.
struct LowerTokenFree : IdrPattern<TokenFreeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(TokenFreeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    const idr::runtime::Function &free = claims(op.getToken().getType(), Unique::Deep)
                                             ? idr::runtime::helper::freeToken
                                             : idr::runtime::helper::freeMaybeToken;
    runtime.call(rewriter, op.getLoc(), free, adaptor.getToken().front());
    rewriter.eraseOp(op);
    return success();
  }
};

// The null token: no cell.
struct LowerTokenNull : IdrPattern<TokenNullOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(TokenNullOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    rewriter.replaceOp(op, LLVM::ZeroOp::create(rewriter, op.getLoc(), ptrType(getContext())));
    return success();
  }
};

} // namespace

void populateCountingPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                              const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerDup, LowerDrop, LowerTake, LowerTakeInto, LowerMatchUnique, LowerTokenFree,
               LowerTokenNull>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
