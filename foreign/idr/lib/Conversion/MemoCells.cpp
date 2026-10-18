// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower for the writes of a memo cell's state. A force is a
// call of its memo sum's dispatch function, which matches the cell's state;
// a label's case marks the cell running before it calls the label's
// function and settles it with the value after. Each is a write of the
// cell's header, and a settle also a write of the value into the forced
// state's field: the cell is allocated at its largest state's size, so
// every state fits it. Neither counts: what the cell holds before and after
// is the owned stage's to account for.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Transforms/DialectConversion.h"

// The runtime's C ABI: the stack mark of a cell's info is a macro.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// Writes the header of the memo cell `cell` in the state laid out as
// `state`, with the words after it the state's layout has. The stack mark
// stays in every state the cell is written in: its memory is its frame's.
void writeState(OpBuilder &b, Location loc, Runtime &runtime, Value cell,
                const layout::Cell &state) {
  Value stack = LLVM::AndOp::create(b, loc, runtime.loadInfo(b, loc, cell),
                                    i32Constant(b, loc, IDRIS_RT_STACK_CELL));
  runtime.storeInfo(b, loc, cell,
                    LLVM::OrOp::create(b, loc, i32Constant(b, loc, state.info.word()), stack));
  runtime.storeCellWords(b, loc, cell, state);
}

// The cell is running: a force that meets it again is the loop the
// dispatch function crashes on.
struct LowerMemoEnter : IdrPattern<MemoEnterOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(MemoEnterOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    DataType memo = dataTypeOf(op.getCell().getType());
    writeState(rewriter, op.getLoc(), runtime, adaptor.getCell().front(),
               layouts.box(memo).cell(memo.getRunningTag()));
    rewriter.eraseOp(op);
    return success();
  }
};

// The cell is forced with the value, which moves into the forced state's
// field.
struct LowerMemoSettle : IdrPattern<MemoSettleOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(MemoSettleOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Value cell = adaptor.getCell().front();
    DataType memo = dataTypeOf(op.getCell().getType());
    const layout::Cell &forced = layouts.box(memo).cell(memo.getForcedTag());
    runtime.store(rewriter, loc, cell, cellAlignment(), forced.fields.front(), adaptor.getValue());
    writeState(rewriter, loc, runtime, cell, forced);
    rewriter.eraseOp(op);
    return success();
  }
};

} // namespace

void populateMemoPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerMemoEnter, LowerMemoSettle>(converter, patterns.getContext(), layouts,
                                                runtime);
}

} // namespace idr::conversion
