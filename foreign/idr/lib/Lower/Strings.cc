// Lowering of the string builders over lists: idr.str.pack over a list of
// characters and idr.str.concat over a list of strings. The list is a box
// of a nil without fields and a cons of the element and the rest. Each op
// walks it twice: once to count the bytes and scalar values of the result
// and whether it is ASCII, which the runtime's one allocation needs; once
// more to write each element after the last. The list is read and never
// counted: the op borrows it. The ops declare the allocation of their result
// and not these reads: a list's cells never change while a reference to them
// is live, and the owned stage's verifier refuses a builder that reads its
// list, a view, once the reference the view borrows is gone, as it refuses a
// field read.

#include "Lower/Patterns.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"

using namespace mlir;

namespace idr::lower {

namespace {

Type ptrType(MLIRContext *ctx) { return LLVM::LLVMPointerType::get(ctx); }

Value i64Constant(OpBuilder &b, Location loc, int64_t value) {
  return arith::ConstantOp::create(b, loc, b.getI64IntegerAttr(value));
}

// The body of a walk: the head's components and the values the walk
// carries, giving the carried values after this element.
using Step = function_ref<SmallVector<Value>(OpBuilder &, Location, ValueRange head,
                                             ValueRange carried)>;

// Walks the list at `cell` while it is a cons, carrying `inits` through
// `step`; gives the carried values at the nil.
SmallVector<Value> walk(OpBuilder &b, Location loc, Layouts &layouts, Runtime &runtime,
                        CtorOp cons, Value cell, ValueRange inits, Step step) {
  SmallVector<Type> types{cell.getType()};
  SmallVector<Value> operands{cell};
  for (Value init : inits) {
    types.push_back(init.getType());
    operands.push_back(init);
  }
  auto loop = scf::WhileOp::create(
      b, loc, types, operands,
      [&](OpBuilder &before, Location l, ValueRange args) {
        Value tag = runtime.loadTag(before, l, args[0]);
        Value consTag = arith::ConstantOp::create(
            before, l, before.getIntegerAttr(tag.getType(), static_cast<int64_t>(cons.getTag())));
        Value isCons = arith::CmpIOp::create(before, l, arith::CmpIPredicate::eq, tag, consTag);
        scf::ConditionOp::create(before, l, isCons, args);
      },
      [&](OpBuilder &after, Location l, ValueRange args) {
        const Cell &layout = layouts.box(cons);
        SmallVector<Value> head = runtime.load(after, l, args[0], layout.fields[0]);
        SmallVector<Value> rest = runtime.load(after, l, args[0], layout.fields[1]);
        SmallVector<Value> carried = step(after, l, head, args.drop_front());
        SmallVector<Value> yields{rest.front()};
        yields.append(carried.begin(), carried.end());
        scf::YieldOp::create(after, l, yields);
      });
  return SmallVector<Value>(loop.getResults().drop_front());
}

// The new string of the counts a first walk gave.
Value allocate(OpBuilder &b, Location loc, Runtime &runtime, Value bytes, Value scalars,
               Value ascii) {
  Value asciiWord = arith::ExtUIOp::create(b, loc, b.getI32Type(), ascii);
  return runtime.call(b, loc, "idris_rt_str_alloc", ptrType(b.getContext()),
                      ValueRange{bytes, scalars, asciiWord});
}

// The bytes a character takes in UTF-8: 1 below 0x80, 2 below 0x800, 3
// below 0x10000, else 4.
Value utf8Length(OpBuilder &b, Location loc, Value c) {
  Value wide = arith::ExtUIOp::create(b, loc, b.getI64Type(), c);
  auto below = [&](int64_t limit) {
    return arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ult, wide, i64Constant(b, loc, limit));
  };
  Value four = i64Constant(b, loc, 4);
  Value three = arith::SelectOp::create(b, loc, below(0x10000), i64Constant(b, loc, 3), four);
  Value two = arith::SelectOp::create(b, loc, below(0x800), i64Constant(b, loc, 2), three);
  return arith::SelectOp::create(b, loc, below(0x80), i64Constant(b, loc, 1), two);
}

Value isAscii(OpBuilder &b, Location loc, Value c) {
  return arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ult, c,
                               arith::ConstantOp::create(b, loc, b.getI32IntegerAttr(0x80)));
}

struct LowerStrPack : IdrPattern<StrPackOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(StrPackOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    CtorOp cons = listCons(op, op.getList().getType(), rewriter.getI32Type());
    if (!cons)
      return failure();
    Value cell = adaptor.getList().front();
    Value yes = arith::ConstantOp::create(rewriter, loc, rewriter.getBoolAttr(true));
    SmallVector<Value> counts =
        walk(rewriter, loc, layouts, runtime, cons, cell,
             {i64Constant(rewriter, loc, 0), i64Constant(rewriter, loc, 0), yes},
             [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
               Value c = head.front();
               Value bytes = arith::AddIOp::create(b, l, carried[0], utf8Length(b, l, c));
               Value scalars = arith::AddIOp::create(b, l, carried[1], i64Constant(b, l, 1));
               Value ascii = arith::AndIOp::create(b, l, carried[2], isAscii(b, l, c));
               return SmallVector<Value>{bytes, scalars, ascii};
             });
    Value s = allocate(rewriter, loc, runtime, counts[0], counts[1], counts[2]);
    walk(rewriter, loc, layouts, runtime, cons, cell, {i64Constant(rewriter, loc, 0)},
         [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
           Value next = runtime.call(b, l, "idris_rt_str_put_char", b.getI64Type(),
                                     ValueRange{s, carried[0], head.front()});
           return SmallVector<Value>{next};
         });
    rewriter.replaceOpWithMultiple(op, {{s}});
    return success();
  }
};

struct LowerStrConcat : IdrPattern<StrConcatOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(StrConcatOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    CtorOp cons = listCons(op, op.getList().getType(), StrType::get(getContext()));
    if (!cons)
      return failure();
    Value cell = adaptor.getList().front();
    Value yes = arith::ConstantOp::create(rewriter, loc, rewriter.getBoolAttr(true));
    SmallVector<Value> counts =
        walk(rewriter, loc, layouts, runtime, cons, cell,
             {i64Constant(rewriter, loc, 0), i64Constant(rewriter, loc, 0), yes},
             [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
               Value part = head.front();
               Value bytes = arith::AddIOp::create(
                   b, l, carried[0],
                   runtime.call(b, l, "idris_rt_str_bytes_length", b.getI64Type(), part));
               Value scalars = arith::AddIOp::create(
                   b, l, carried[1], runtime.call(b, l, "idris_rt_str_length", b.getI64Type(), part));
               Value partAscii = runtime.call(b, l, "idris_rt_str_is_ascii", b.getI32Type(), part);
               Value nonzero = arith::CmpIOp::create(
                   b, l, arith::CmpIPredicate::ne, partAscii,
                   arith::ConstantOp::create(b, l, b.getI32IntegerAttr(0)));
               Value ascii = arith::AndIOp::create(b, l, carried[2], nonzero);
               return SmallVector<Value>{bytes, scalars, ascii};
             });
    Value s = allocate(rewriter, loc, runtime, counts[0], counts[1], counts[2]);
    walk(rewriter, loc, layouts, runtime, cons, cell, {i64Constant(rewriter, loc, 0)},
         [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
           Value next = runtime.call(b, l, "idris_rt_str_put_str", b.getI64Type(),
                                     ValueRange{s, carried[0], head.front()});
           return SmallVector<Value>{next};
         });
    rewriter.replaceOpWithMultiple(op, {{s}});
    return success();
  }
};

} // namespace

void populateStringPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                            Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerStrPack, LowerStrConcat>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::lower
