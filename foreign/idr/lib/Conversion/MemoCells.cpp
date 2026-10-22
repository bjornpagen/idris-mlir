// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower for the exchange of a memo cell's state. A force is
// a call of its memo sum's dispatch function, which matches the cell's
// state; a label's case is a memo.run, which reads the label's captures out
// of the cell, writes the cell's header Running, runs its region on the
// captures, and writes the value into the forced state's field and the
// header Forced. The cell is allocated at its largest state's size, so
// every state fits it. Nothing counts: the captures move out with the
// references the cell held, and the value moves in with its own, as
// counting accounted for. A static memo cell's value is static data where
// its type says so, a fact of its lifetime, so the force writes no mark of
// its own.

#include "Lower/Lower.h"

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
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

// The captures move out of the label's fields into the region's
// arguments, the cell is Running while the region runs, here, as an
// scf.execute_region whose yield is the region's, and the first value it
// yields moves into the forced state's field, the cell Forced; the values
// after it are the op's results. A region that never returns ends as it
// is, in ub.unreachable.
struct LowerMemoRun : IdrPattern<MemoRunOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(MemoRunOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    auto memo = cast<DataType>(unrestricted(op.getCell().getType()));
    families::MemoView states = *memo.memo();
    // What the region yields, as the converter gives it, the one source of
    // the region's converted signature: the value, then each result. Asked
    // before any op is made, so a type the converter does not take leaves
    // the op as it is.
    SmallVector<Type> types{memo.ctor(states.forced()).fields.front()};
    llvm::append_range(types, op.getOuts().getTypes());
    SmallVector<SmallVector<Type>> yielded(types.size());
    for (auto [type, converted] : llvm::zip_equal(types, yielded))
      if (failed(getTypeConverter()->convertType(type, converted)))
        return rewriter.notifyMatchFailure(op, "a value the region yields has no lowered type");
    Value cell = adaptor.getCell().front();
    const layout::CellLayout &cells = layouts.cells(memo);
    const layout::Cell &label = cells.cell(Tag{op.getTag()});
    SmallVector<SmallVector<Value>> captures;
    for (BlockArgument capture : op.getRegion().getArguments())
      captures.push_back(runtime.load(rewriter, loc, cell, cellAlignment(),
                                      label.fields[capture.getArgNumber()], Contents::MayChange));
    writeState(rewriter, loc, runtime, cell, cells.cell(states.running()));
    SmallVector<Type> flat;
    for (ArrayRef<Type> components : yielded)
      llvm::append_range(flat, components);
    auto run = scf::ExecuteRegionOp::create(rewriter, loc, flat);
    // The exchange's own end gives the value and the results: the yield of
    // the region the op becomes.
    if (auto end = dyn_cast<MemoYieldOp>(op.getRegion().front().getTerminator())) {
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPoint(end);
      rewriter.replaceOpWithNewOp<scf::YieldOp>(end, end.getValues());
    }
    moveRegion(rewriter, *getTypeConverter(), op.getRegion(), captures, run.getRegion());
    ValueRange values = run.getResults();
    const layout::Cell &forced = cells.cell(states.forced());
    runtime.store(rewriter, loc, cell, cellAlignment(), forced.fields.front(),
                  values.take_front(yielded.front().size()));
    writeState(rewriter, loc, runtime, cell, forced);
    rewriter.replaceOpWithMultiple(
        op, groupResults(values.drop_front(yielded.front().size()), ArrayRef(yielded).drop_front()));
    return success();
  }
};

} // namespace

void populateMemoPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerMemoRun>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
