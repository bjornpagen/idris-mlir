// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower for the exchange of a memo cell's state. A force is
// a call of its memo sum's dispatch function, which matches the cell's
// state; a label's case exchanges the cell's state in two steps, which
// phase 1 has made of every exchange still whole: memo.take reads the
// label's captures out of the cell and writes its header Running, the
// label's code runs on them in place, and memo.store writes the value into
// the forced state's field and the header Forced, each value re-packed
// between its type and the type its slot is laid out at, as every field
// is. The cell is allocated at its largest state's size, so every state
// fits it. Nothing counts: the captures move out with the references the
// cell held, and the value moves in with its own, as counting accounted
// for. A static memo cell's value is static data where its type says so, a
// fact of its lifetime, so the force writes no mark of its own.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The memo cell `cell` in the state laid out as `state`: its header's info
// word and the words after it the state's layout has.
void writeState(OpBuilder &b, Location loc, const Runtime &runtime, Value cell,
                const layout::Cell &state) {
  runtime.storeInfoAndWords(b, loc, cell, state);
}

// The captures move out of the label's fields, each re-packed from its
// slot's type into the type it is taken at, and the cell is Running from
// then on.
struct LowerMemoTake : IdrPattern<MemoTakeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(MemoTakeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType memo = op.getDataType();
    Value cell = adaptor.getCell().front();
    const layout::CellLayout &cells = layouts.cells(memo);
    const layout::Cell &label = cells.cell(op.getTag());
    SmallVector<SmallVector<Value>> captures;
    for (auto [capture, slots, slot] :
         llvm::zip_equal(op.getCaptures(), label.fields, layouts.fieldTypes(memo, op.getTag())))
      captures.push_back(repack(rewriter, loc, layouts, runtime, slot, capture.getType(),
                                runtime.load(rewriter, loc, cell, cellAlignment(), slots,
                                             Contents::MayChange),
                                takesOf(capture.getType())));
    writeState(rewriter, loc, runtime, cell, cells.cell(memo.memo()->running()));
    rewriter.replaceOpWithMultiple(op, std::move(captures));
    return success();
  }
};

// The value moves into the forced state's field, re-packed from its type
// at the cell's indices into the type the field is laid out at, and the
// cell is Forced.
struct LowerMemoStore : IdrPattern<MemoStoreOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(MemoStoreOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType memo = op.getDataType();
    Value cell = adaptor.getCell().front();
    Tag state = memo.memo()->forced();
    const layout::Cell &forced = layouts.cells(memo).cell(state);
    Type value = op.getValue().getType();
    runtime.store(rewriter, loc, cell, cellAlignment(), forced.fields.front(),
                  repack(rewriter, loc, layouts, runtime, value,
                         layouts.fieldTypes(memo, state).front(), adaptor.getValue(),
                         takesOf(value)));
    writeState(rewriter, loc, runtime, cell, forced);
    rewriter.eraseOp(op);
    return success();
  }
};

} // namespace

void populateMemoPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerMemoTake, LowerMemoStore>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
