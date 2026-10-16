// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the string builders over lists: idr.str.pack over a list of
// characters and idr.str.concat over a list of strings; and of
// idr.io.put_list, which writes such a list. The list is a box of a nil
// without fields and a cons of the element and the rest. Each builder walks
// it twice: once to count the bytes and scalar values of the result and
// whether it is ASCII, which the runtime's one allocation needs; once more to
// write each element after the last. Output walks it once. The list is read
// and never counted: the op borrows it. The ops do not declare these reads (a
// builder declares the allocation of its result, output its IO): a list's
// cells never change while a reference to them is live, and the owned stage's
// verifier refuses an op that reads its list, a view, once the reference the
// view borrows is gone, as it refuses a field read.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Symbols.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Transforms/DialectConversion.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The list a builder or an output walks: base's list, whose body says
// which constructor is the cons (the ops' verifiers hold it to that).
DataType listOf(Type type) { return dataTypeOf(type); }

// The body of a walk: the head's components and the values the walk
// carries, giving the carried values after this element.
using Step = function_ref<SmallVector<Value>(OpBuilder &, Location, ValueRange head,
                                             ValueRange carried)>;

// Walks the list at `cell` while it is a cons, carrying `inits` through
// `step`; gives the carried values at the nil.
SmallVector<Value> walk(OpBuilder &b, Location loc, const Layouts &layouts, Runtime &runtime,
                        DataType list, Value cell, ValueRange inits, Step step) {
  SmallVector<Type> types{cell.getType()};
  SmallVector<Value> operands{cell};
  for (Value init : inits) {
    types.push_back(init.getType());
    operands.push_back(init);
  }
  auto loop = scf::WhileOp::create(
      b, loc, types, operands,
      [&](OpBuilder &before, Location l, ValueRange args) {
        Value tag = runtime.loadTag(before, l, args[0], list, layouts);
        Value consTag = arith::ConstantIntOp::create(
            before, l, static_cast<uint32_t>(list.getConsTag()), 64);
        Value isCons = arith::CmpIOp::create(before, l, arith::CmpIPredicate::eq, tag, consTag);
        scf::ConditionOp::create(before, l, isCons, args);
      },
      [&](OpBuilder &after, Location l, ValueRange args) {
        const layout::Cell &layout = layouts.box(list, list.getConsTag());
        Value cons = args[0];
        SmallVector<Value> head = runtime.load(after, l, cons, cellAlignment(), layout.fields[0]);
        SmallVector<Value> rest = runtime.load(after, l, cons, cellAlignment(), layout.fields[1]);
        SmallVector<Value> carried = step(after, l, head, args.drop_front());
        SmallVector<Value> yields{rest.front()};
        yields.append(carried.begin(), carried.end());
        scf::YieldOp::create(after, l, yields);
      });
  return SmallVector<Value>(loop.getResults().drop_front());
}

// The new string of the counts a first walk gave. Whether it is ASCII is
// whether the two counts are equal, which the runtime reads off them.
Value allocate(OpBuilder &b, Location loc, Runtime &runtime, Value bytes, Value scalars) {
  return runtime.call(b, loc, "idris_rt_str_alloc", ptrType(b.getContext()),
                      ValueRange{bytes, scalars});
}

// pack and concat walk a list the same way: once for the bytes and the
// scalar values, then once to write each element after the last. A
// character's sizes and a string's are the runtime's.
template <typename OpT>
struct LowerStringOfList : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    constexpr bool packing = std::is_same_v<OpT, StrPackOp>;
    Location loc = op.getLoc();
    DataType list = listOf(op.getList().getType());
    Value cell = adaptor.getList().front();
    Value zero = arith::ConstantIntOp::create(rewriter, loc, 0, 64);
    SmallVector<Value> counts =
        walk(rewriter, loc, this->layouts, this->runtime, list, cell, {zero, zero},
             [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
               Value item = head.front();
               Value bytes, scalars;
               if constexpr (packing) {
                 bytes = arith::AddIOp::create(
                     b, l, carried[0],
                     this->runtime.call(b, l,
                                        idr::runtime::Abi<StrScalarBytesOp>::functions[0].symbol,
                                        b.getI64Type(), item));
                 Value one = arith::ConstantIntOp::create(b, l, 1, 64);
                 scalars = arith::AddIOp::create(b, l, carried[1], one);
               } else {
                 bytes = arith::AddIOp::create(
                     b, l, carried[0],
                     this->runtime.call(b, l, "idris_rt_str_bytes_length", b.getI64Type(), item));
                 scalars = arith::AddIOp::create(
                     b, l, carried[1],
                     this->runtime.call(b, l, "idris_rt_str_length", b.getI64Type(), item));
               }
               return SmallVector<Value>{bytes, scalars};
             });
    Value s = allocate(rewriter, loc, this->runtime, counts[0], counts[1]);
    walk(rewriter, loc, this->layouts, this->runtime, list, cell, {zero},
         [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
           StringRef put = packing ? "idris_rt_str_put_char" : "idris_rt_str_put_str";
           Value next = this->runtime.call(b, l, put, b.getI64Type(),
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
    DataType list = listOf(op.getList().getType());
    Type element = list.getListElement();
    StringRef put = isa<StrType>(unrestricted(element)) ? "idris_rt_io_put_str"
                                                        : "idris_rt_io_put_char";
    walk(rewriter, op.getLoc(), layouts, runtime, list, adaptor.getList().front(), {},
         [&](OpBuilder &b, Location l, ValueRange head, ValueRange) {
           runtime.perform(b, l, put, head.front());
           return SmallVector<Value>{};
         });
    // A world has no runtime form.
    rewriter.replaceOpWithMultiple(op, {SmallVector<Value>{}});
    return success();
  }
};

} // namespace

// The string builders over lists, and the output of such a list.
void populateStringPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                            const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerStringOfList<StrPackOp>, LowerStringOfList<StrConcatOp>, LowerPutList>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
