// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the ops that count references: calls of the runtime,
// which LTO inlines.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/Fields.h"
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

// One more reference for each counted component; static data, which holds
// no count, takes none (Runtime::inc).
struct LowerDup : IdrPattern<DupOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DupOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    ValueRange components = adaptor.getValue();
    runtime.inc(rewriter, op.getLoc(), components, layouts.counted(op.getValue().getType()));
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(components)});
    return success();
  }
};

// One less for each counted component, and none for static data
// (Runtime::dec); a token's memory is freed.
struct LowerDrop : IdrPattern<DropOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DropOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Type type = op.getValue().getType();
    if (isa<TokenType>(unrestricted(type)))
      runtime.perform(rewriter, op.getLoc(), "idris_rt_free_cell", adaptor.getValue().front());
    else
      runtime.dec(rewriter, op.getLoc(), adaptor.getValue(), layouts.counted(type));
    rewriter.eraseOp(op);
    return success();
  }
};

// The token's cell, or a new cell when the token is null, holding the
// constructor, and the destination of each of its holes. A reuse of the
// constructor its token's take took apart finds the header in the cell
// already, and every field it gives back as taken (Fields): those are
// stored into a new cell only, and the header is left as it is.
struct LowerReuse : IdrPattern<ReuseOp> {
  LowerReuse(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts,
             Runtime &runtime, const Fields &fields)
      : IdrPattern(converter, ctx, layouts, runtime), fields(fields) {}

  LogicalResult matchAndRewrite(ReuseOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    Tag tag = op.getTag();
    const layout::Cell &layout = layouts.box(op.getDataType(), tag);
    layout::CellInfo info = layout.info;
    std::optional<ArrayRef<bool>> kept = fields.kept(op);
    SmallVector<SmallVector<Value>> values =
        fieldsOf(rewriter, loc, layout, op.getHoles(), adaptor.getFields());
    // The fields `cell` holds already when `held`, the others otherwise.
    auto store = [&](OpBuilder &b, Value cell, bool held) {
      for (auto [index, slots, field] : llvm::enumerate(layout.fields, values))
        if ((kept && (*kept)[index]) == held)
          runtime.store(b, loc, cell, cellAlignment(), slots, field);
    };
    Value token = adaptor.getToken().front();
    Type ptr = token.getType();
    Value where;
    if (isExclusive(op.getToken().getType())) {
      // An exclusive token is the cell, certainly: no test.
      if (!kept)
        runtime.storeHeader(rewriter, loc, token, layout, tag, info);
      where = token;
    } else {
      Value empty = LLVM::ICmpOp::create(rewriter, loc, LLVM::ICmpPredicate::eq, token,
                                         nullComponent(rewriter, loc, ptr));
      auto choose =
          scf::IfOp::create(rewriter, loc, TypeRange{ptr}, empty, /*withElseRegion=*/true);
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      Value fresh = runtime.allocate(rewriter, loc, layout, tag);
      store(rewriter, fresh, /*held=*/true);
      scf::YieldOp::create(rewriter, loc, fresh);
      rewriter.setInsertionPointToStart(choose.elseBlock());
      if (!kept)
        runtime.storeHeader(rewriter, loc, token, layout, tag, info);
      scf::YieldOp::create(rewriter, loc, token);
      where = choose.getResult(0);
    }
    store(rewriter, where, /*held=*/false);
    SmallVector<SmallVector<Value>> out{{where}};
    llvm::append_range(out, destsOf(rewriter, loc, where, layout, op.getHoles()));
    rewriter.replaceOpWithMultiple(op, std::move(out));
    return success();
  }

  const Fields &fields;
};

// A sum's fields are its slots, and move as they are. A box's fields are
// loaded; when the box held the only reference to its cell they move out of
// it and the token is the cell, otherwise they each get one more
// reference, the box drops its own, and the token is null. A field nothing
// wants, whose one use is an idr.drop, dies with the box, its dup and drop
// fused: where the box held the only reference the field's own is dropped
// here, and where the box was shared nothing happens to the field, instead
// of a reference taken for it and given up again.
struct LowerTake : IdrPattern<TakeOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(TakeOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    DataType data = op.getDataType();
    Tag tag = op.getTag();
    ValueRange value = adaptor.getValue();
    SmallVector<SmallVector<Value>> out;
    if (!isBoxed(op.getValue().getType())) {
      for (unsigned index = 0, e = static_cast<unsigned>(op.getFields().size()); index < e; ++index)
        out.push_back(unboxedField(layouts.sum(data), value, tag, index));
      rewriter.replaceOpWithMultiple(op, std::move(out));
      return success();
    }
    Value cell = value.front();
    // A constructor without fields is its atom: nothing is loaded, and
    // nothing is anyone's to free.
    if (!op.getToken()) {
      rewriter.eraseOp(op);
      return success();
    }
    const layout::Cell &layout = layouts.box(data, tag);
    SmallVector<DropOp> drops;
    for (Value field : op.getFields())
      drops.push_back(field.hasOneUse() ? dyn_cast<DropOp>(*field.user_begin()) : DropOp());
    // The components of the fields that move on and of those that die
    // here, each with whether it is counted.
    SmallVector<Value> moving, dying;
    SmallVector<bool> movingCounted, dyingCounted;
    ArrayRef<Type> fieldTypes = data.getCtor(tag).fields;
    for (auto [index, slots, fieldType] : llvm::enumerate(layout.fields, fieldTypes)) {
      out.push_back(runtime.load(rewriter, loc, cell, cellAlignment(), slots));
      bool dies = drops[index] != nullptr;
      llvm::append_range(dies ? dying : moving, out.back());
      llvm::append_range(dies ? dyingCounted : movingCounted, layouts.counted(fieldType));
    }
    Value token = cell;
    // An exclusive value alone reaches its cell: its fields move out, and
    // the cell is the token, with no test.
    if (isExclusive(op.getValue().getType())) {
      runtime.dec(rewriter, loc, dying, dyingCounted);
    } else {
      Type ptr = cell.getType();
      auto choose = scf::IfOp::create(rewriter, loc, TypeRange{ptr},
                                      runtime.exclusive(rewriter, loc, cell),
                                      /*withElseRegion=*/true);
      OpBuilder::InsertionGuard guard(rewriter);
      rewriter.setInsertionPointToStart(choose.thenBlock());
      runtime.dec(rewriter, loc, dying, dyingCounted);
      scf::YieldOp::create(rewriter, loc, cell);
      rewriter.setInsertionPointToStart(choose.elseBlock());
      runtime.inc(rewriter, loc, moving, movingCounted);
      runtime.dec(rewriter, loc, cell, {true});
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
                              const Layouts &layouts, Runtime &runtime, const Fields &fields) {
  MLIRContext *ctx = patterns.getContext();
  // A cell an allocation gave, adopted as owned, and an owned value given to
  // a store, change no count: each is its operand.
  patterns.add<LowerDup, LowerDrop, LowerTake, LowerAsItself<BorrowOp>, LowerAsItself<ShareOp>,
               LowerAsItself<OwnAdoptOp>, LowerAsItself<OwnGiveOp>>(converter, ctx, layouts,
                                                                     runtime);
  patterns.add<LowerReuse>(converter, ctx, layouts, runtime, fields);
}

} // namespace idr::conversion
