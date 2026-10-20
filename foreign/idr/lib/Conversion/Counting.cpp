// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the ops that count references: calls of the runtime,
// which LTO inlines.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
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

// One more reference for each reference the value holds; static data,
// which holds no count, takes none (Runtime::inc).
struct LowerDup : IdrPattern<DupOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DupOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    ValueRange components = adaptor.getValue();
    runtime.inc(rewriter, op.getLoc(),
                references(layouts.components(op.getValue().getType()), components));
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(components)});
    return success();
  }
};

// One less for each reference, and none for static data (Runtime::dec). A
// token is a cell its take emptied, which holds no reference and no count:
// its memory is freed.
struct LowerDrop : IdrPattern<DropOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DropOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Type type = op.getValue().getType();
    if (isa<TokenType>(unrestricted(type)))
      runtime.call(rewriter, op.getLoc(), idr::runtime::helper::freeCell,
                   adaptor.getValue().front());
    else
      runtime.dec(rewriter, op.getLoc(), references(layouts.components(type), adaptor.getValue()));
    rewriter.eraseOp(op);
    return success();
  }
};

// The take of a cell: its fields are loaded; when the box held the only
// reference to its cell they move out of it and the token is the cell,
// otherwise they each get one more reference, the box drops its own, and
// the token is null. A field nothing wants, whose one use is an idr.drop,
// dies with the box, its dup and drop fused: where the box held the only
// reference the field's own is dropped here, and where the box was shared
// nothing happens to the field, instead of a reference taken for it and
// given up again.
struct LowerTake : IdrPattern<TakeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(TakeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType data = op.getDataType();
    Tag tag = op.getTag();
    Value cell = adaptor.getValue().front();
    const layout::Cell &layout = layouts.box(data).cell(tag);
    SmallVector<DropOp> drops;
    for (Value field : op.getFields())
      drops.push_back(field.hasOneUse() ? dyn_cast<DropOp>(*field.user_begin()) : DropOp());
    // The references of the fields that move on and of those that die here.
    SmallVector<SmallVector<Value>> out;
    SmallVector<Value> moving, dying;
    ArrayRef<Type> fieldTypes = data.getCtor(tag).fields;
    for (auto [index, slots, fieldType] : llvm::enumerate(layout.fields, fieldTypes)) {
      out.push_back(runtime.load(rewriter, loc, cell, cellAlignment(), slots));
      llvm::append_range(drops[index] ? dying : moving,
                         references(layouts.components(fieldType), out.back()));
    }
    Value token = cell;
    // An exclusive value alone reaches its cell: its fields move out, and
    // the cell is the token, with no test. Any other is tested at run time:
    // the grade is what Idris and counting proved, and a value they proved
    // nothing of may still hold the only reference.
    if (isExclusive(op.getValue().getType())) {
      runtime.dec(rewriter, loc, dying);
    } else {
      Type ptr = cell.getType();
      auto choose = scf::IfOp::create(rewriter, loc, TypeRange{ptr},
                                      runtime.exclusive(rewriter, loc, cell),
                                      /*withElseRegion=*/true);
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      runtime.dec(rewriter, loc, dying);
      scf::YieldOp::create(rewriter, loc, cell);
      rewriter.setInsertionPointToStart(choose.elseBlock());
      runtime.inc(rewriter, loc, moving);
      runtime.dec(rewriter, loc, cell);
      scf::YieldOp::create(rewriter, loc, nullComponent(rewriter, loc, ptr));
      token = choose.getResult(0);
    }
    for (DropOp drop : drops)
      if (drop)
        rewriter.eraseOp(drop);
    out.insert(out.begin(), SmallVector<Value>{token});
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }
};

} // namespace

// The patterns of the ops that count references.
void populateCountingPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                              const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerDup, LowerDrop, LowerTake>(converter, patterns.getContext(), layouts,
                                               runtime);
}

} // namespace idr::conversion
