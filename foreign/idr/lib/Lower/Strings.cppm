// idr.lower:strings: the patterns of the string builders over lists:
// idr.str.pack over a list of characters and idr.str.concat over a list of
// strings; and of idr.io.put_list, which writes such a list. The list is a box of a nil
// without fields and a cons of the element and the rest. Each builder walks
// it twice: once to count the bytes and scalar values of the result and
// whether it is ASCII, which the runtime's one allocation needs; once more
// to write each element after the last. Output walks it once. The list is
// read and never counted: the op borrows it. The ops do not declare these
// reads (a builder declares the allocation of its result, output its IO): a
// list's cells never change while a reference to them is live, and the
// owned stage's verifier refuses an op that reads its list, a view, once the
// reference the view borrows is gone, as it refuses a field read.

export module idr.lower:strings;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :idrPattern;
import :runtime;
import :words;

using namespace mlir;

namespace idr::lower {

namespace {

// The body of a walk: the head's components and the values the walk
// carries, giving the carried values after this element.
using Step = function_ref<SmallVector<Value>(OpBuilder &, Location, ValueRange head,
                                             ValueRange carried)>;

// Walks the list at `cell` while it is a cons, carrying `inits` through
// `step`; gives the carried values at the nil.
SmallVector<Value> walk(OpBuilder &b, Location loc, layout::Layouts &layouts, Runtime &runtime,
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
        const layout::Cell &layout = layouts.box(cons);
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
    return arith::CmpIOp::create(b, loc, arith::CmpIPredicate::ult, wide, constantI64(b, loc, limit));
  };
  Value four = constantI64(b, loc, 4);
  Value three = arith::SelectOp::create(b, loc, below(0x10000), constantI64(b, loc, 3), four);
  Value two = arith::SelectOp::create(b, loc, below(0x800), constantI64(b, loc, 2), three);
  return arith::SelectOp::create(b, loc, below(0x80), constantI64(b, loc, 1), two);
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
             {constantI64(rewriter, loc, 0), constantI64(rewriter, loc, 0), yes},
             [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
               Value c = head.front();
               Value bytes = arith::AddIOp::create(b, l, carried[0], utf8Length(b, l, c));
               Value scalars = arith::AddIOp::create(b, l, carried[1], constantI64(b, l, 1));
               Value ascii = arith::AndIOp::create(b, l, carried[2], isAscii(b, l, c));
               return SmallVector<Value>{bytes, scalars, ascii};
             });
    Value s = allocate(rewriter, loc, runtime, counts[0], counts[1], counts[2]);
    walk(rewriter, loc, layouts, runtime, cons, cell, {constantI64(rewriter, loc, 0)},
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
             {constantI64(rewriter, loc, 0), constantI64(rewriter, loc, 0), yes},
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
    walk(rewriter, loc, layouts, runtime, cons, cell, {constantI64(rewriter, loc, 0)},
         [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
           Value next = runtime.call(b, l, "idris_rt_str_put_str", b.getI64Type(),
                                     ValueRange{s, carried[0], head.front()});
           return SmallVector<Value>{next};
         });
    rewriter.replaceOpWithMultiple(op, {{s}});
    return success();
  }
};

// The output of a list in one walk: each character or string goes to the
// runtime's output as put_char or put_str writes it, so the bytes, and
// their order with everything else the program writes, are those of
// writing the list's pack or concat.
struct LowerPutList : IdrPattern<PutListOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(PutListOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Type element = op.getElementType();
    CtorOp cons = listCons(op, op.getList().getType(), element);
    if (!cons)
      return failure();
    StringRef put = isa<StrType>(element) ? "idris_rt_io_put_str" : "idris_rt_io_put_char";
    walk(rewriter, op.getLoc(), layouts, runtime, cons, adaptor.getList().front(), {},
         [&](OpBuilder &b, Location l, ValueRange head, ValueRange) {
           runtime.call(b, l, put, Type(), head.front());
           return SmallVector<Value>{};
         });
    // A world has no runtime form.
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
    return success();
  }
};

} // namespace

// The string builders over lists, and the output of such a list.
export void populateStringPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                                   layout::Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerStrPack, LowerStrConcat, LowerPutList>(converter, patterns.getContext(),
                                                           layouts, runtime);
}

} // namespace idr::lower
