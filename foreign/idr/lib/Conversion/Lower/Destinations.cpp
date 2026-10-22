// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The places written once through a destination. A destination is one
// address per component of what it writes, each that component's slot in
// its place: a hole of a cell an init built, or the slot a function waiting
// for a row's answers keeps on its frame for one of them. A write is one
// store per component, with no count changed, since the value's reference
// moves into the place, and none carries an invariant group: a hole is
// written once after its zero, and a load through the cell later sees the
// value. What a destination's type says of the value's grade is the
// verifier's: at run time a value is its components at any grade.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A value written once through its destination: each component stored at
// its own address, aligned as its slot is.
struct LowerDestWrite : IdrPattern<DestWriteOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DestWriteOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    for (auto [address, value] : llvm::zip_equal(adaptor.getDest(), adaptor.getValue()))
      LLVM::StoreOp::create(rewriter, op.getLoc(), value, address,
                            layouts.alignmentOf(value.getType()));
    rewriter.eraseOp(op);
    return success();
  }
};

// A function waiting for a row's answers, each written through its own
// destination: for each result, a slot of the frame per component of it,
// made once in the entry block, which the region's destination of that
// result names; the region runs in place, and each answer is read out of
// its slots when it ends. A row of no result has no slot. A scoped
// result's stated lifetime is no value here.
struct LowerDestAnswer : IdrPattern<DestAnswerOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DestAnswerOp op, OneToNOpAdaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    SmallVector<SmallVector<layout::Component>> rows = llvm::map_to_vector(
        op->getResultTypes(), [&](Type result) { return layouts.components(result); });
    SmallVector<SmallVector<Value>> slots(rows.size());
    {
      OpBuilder::InsertionGuard guard(rewriter);
      Operation *scope = op->getParentWithTrait<mlir::OpTrait::AutomaticAllocationScope>();
      rewriter.setInsertionPointToStart(&scope->getRegion(0).front());
      for (auto [components, places] : llvm::zip_equal(rows, slots))
        for (const layout::Component &component : components)
          places.push_back(LLVM::AllocaOp::create(rewriter, loc, ptrType(getContext()),
                                                  component.type, i64Constant(rewriter, loc, 1),
                                                  layouts.alignmentOf(component.type)));
    }
    auto run = scf::ExecuteRegionOp::create(rewriter, loc, TypeRange{});
    moveRegion(rewriter, *getTypeConverter(), op.getBody(), slots, run.getRegion());
    SmallVector<SmallVector<Value>> answers;
    for (auto [components, places] : llvm::zip_equal(rows, slots)) {
      SmallVector<Value> &answer = answers.emplace_back();
      for (auto [component, slot] : llvm::zip_equal(components, places))
        answer.push_back(LLVM::LoadOp::create(rewriter, loc, component.type, slot,
                                              layouts.alignmentOf(component.type)));
    }
    rewriter.replaceOpWithMultiple(op, std::move(answers));
    return success();
  }
};

} // namespace

void populateDestinationPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                 const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerDestWrite, LowerDestAnswer>(converter, patterns.getContext(), layouts,
                                                runtime);
}

} // namespace idr::conversion
