// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower for the exchange of a memo cell's state. A force is
// a call of its memo sum's dispatch function, which matches the cell's
// state; a label's case exchanges the cell's state in two steps, which
// phase 1 has made of every exchange still whole: memo.take reads the
// label's captures out of the cell and writes its header Running, the
// label's code runs on them in place, and memo.store writes the value into
// the forced state's field and the header Forced. The cell is allocated at
// its largest state's size, so every state fits it. Nothing counts: the
// captures move out with the references the cell held, and the value moves
// in with its own, as counting accounted for. A static memo cell's value is
// static data where its type says so, a fact of its lifetime, so the force
// writes no mark of its own.

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

// The captures move out of the label's fields, each at its read, and the
// cell is Running from then on.
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
    for (OpResult capture : op.getCaptures())
      captures.push_back(runtime.load(rewriter, loc, cell, cellAlignment(),
                                      label.fields[capture.getResultNumber()], Contents::MayChange));
    writeState(rewriter, loc, runtime, cell, cells.cell(memo.memo()->running()));
    rewriter.replaceOpWithMultiple(op, std::move(captures));
    return success();
  }
};

// The value moves into the forced state's field, and the cell is Forced.
struct LowerMemoStore : IdrPattern<MemoStoreOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(MemoStoreOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType memo = op.getDataType();
    Value cell = adaptor.getCell().front();
    const layout::Cell &forced = layouts.cells(memo).cell(memo.memo()->forced());
    runtime.store(rewriter, loc, cell, cellAlignment(), forced.fields.front(), adaptor.getValue());
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
