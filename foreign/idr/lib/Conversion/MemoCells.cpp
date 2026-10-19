// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 2 of idr-lower for the exchange of a memo cell's state. A force is
// a call of its memo sum's dispatch function, which matches the cell's
// state; a label's case is an idr.memo.run, which reads the label's
// captures out of the cell, writes the cell's header Running, runs its
// region on the captures, and writes the value into the forced state's
// field and the header Forced. The cell is allocated at its largest
// state's size, so every state fits it. Nothing counts: the captures move
// out with the references the cell held, and the value moves in with its
// own, as the owned stage accounted for.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
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
    DataType memo = op.getDataType();
    // What the region yields, as the converter gives it, the one source of
    // the region's converted signature: the value, then each result. Asked
    // before any op is made, so a type the converter does not take leaves
    // the op as it is.
    SmallVector<Type> types{memo.getCtor(memo.getForcedTag()).fields.front()};
    llvm::append_range(types, op.getOuts().getTypes());
    SmallVector<SmallVector<Type>> yielded(types.size());
    for (auto [type, converted] : llvm::zip_equal(types, yielded))
      if (failed(getTypeConverter()->convertType(type, converted)))
        return rewriter.notifyMatchFailure(op, "a value the region yields has no lowered type");
    Value cell = adaptor.getCell().front();
    const layout::BoxLayout &box = layouts.box(memo);
    const layout::Cell &label = box.cell(op.getTag());
    TypeConverter::SignatureConversion entry(op.getBody()->getNumArguments());
    // A capture of no component (a sum of atoms held in place) is dropped,
    // as the converter drops an argument it converts to nothing: an empty
    // replacement would read as a position remapped.
    for (BlockArgument capture : op.getCaptures()) {
      unsigned at = capture.getArgNumber();
      SmallVector<Value> loaded =
          runtime.load(rewriter, loc, cell, cellAlignment(), label.fields[at]);
      if (!loaded.empty())
        entry.remapInput(at, loaded);
    }
    writeState(rewriter, loc, runtime, cell, box.cell(memo.getRunningTag()));
    rewriter.applySignatureConversion(op.getBody(), entry, getTypeConverter());
    SmallVector<Type> flat;
    for (ArrayRef<Type> components : yielded)
      llvm::append_range(flat, components);
    auto run = scf::ExecuteRegionOp::create(rewriter, loc, flat);
    rewriter.inlineRegionBefore(op.getRegion(), run.getRegion(), run.getRegion().end());
    ValueRange values = run.getResults();
    const layout::Cell &forced = box.cell(memo.getForcedTag());
    runtime.store(rewriter, loc, cell, cellAlignment(), forced.fields.front(),
                  values.take_front(yielded.front().size()));
    writeState(rewriter, loc, runtime, cell, forced);
    values = values.drop_front(yielded.front().size());
    SmallVector<SmallVector<Value>> results;
    for (ArrayRef<Type> out : ArrayRef(yielded).drop_front()) {
      results.push_back(SmallVector<Value>(values.take_front(out.size())));
      values = values.drop_front(out.size());
    }
    rewriter.replaceOpWithMultiple(op, std::move(results));
    return success();
  }
};

} // namespace

void populateMemoPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                          const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerMemoRun>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
