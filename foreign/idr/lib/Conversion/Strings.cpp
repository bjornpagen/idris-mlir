// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The patterns of the string builders over lists: idr.str.pack over a list of
// characters and idr.str.concat over a list of strings. The list is a cell
// of a nil without fields or of a cons of the element and the rest, as its
// family's shape says (its ListShape). Each builder walks it twice: once to
// count the bytes and scalar values of the result and whether it is ASCII,
// which the runtime's one allocation needs; once more to write each element
// after the last. The list is read and never counted: the op reads it in
// place, and a list's cells never change while a reference to them is
// live. Writing a list's pack or concat, its one use, is the composition
// the lowering emits with no string at all: one walk, each element written
// as idr.io.put_char or idr.io.put_str writes it, where the output stands.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
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

// The list a builder walks, and its shape: which constructor is its cons
// and which field its element, which the op's constraint holds it to.
struct List {
  DataType data;
  families::ListShape shape;
};

List listOf(Type type) {
  auto data = cast<DataType>(unrestricted(type));
  return {data, *data.listShape()};
}

// The body of a walk: the head's components and the values the walk
// carries, giving the carried values after this element.
using Step = function_ref<SmallVector<Value>(OpBuilder &, Location, ValueRange head,
                                             ValueRange carried)>;

// Walks the list at `cell` while it is a cons, carrying `inits` through
// `step`; gives the carried values at the nil.
SmallVector<Value> walk(OpBuilder &b, Location loc, const Layouts &layouts, Runtime &runtime,
                        const List &list, Value cell, ValueRange inits, Step step) {
  SmallVector<Type> types{cell.getType()};
  SmallVector<Value> operands{cell};
  for (Value init : inits) {
    types.push_back(init.getType());
    operands.push_back(init);
  }
  auto loop = scf::WhileOp::create(
      b, loc, types, operands,
      [&](OpBuilder &before, Location l, ValueRange args) {
        Value tag = runtime.loadTag(before, l, args[0], list.data, layouts);
        Value consTag = arith::ConstantIntOp::create(
            before, l, static_cast<uint32_t>(list.shape.cons), 64);
        Value isCons = arith::CmpIOp::create(before, l, arith::CmpIPredicate::eq, tag, consTag);
        scf::ConditionOp::create(before, l, isCons, args);
      },
      [&](OpBuilder &after, Location l, ValueRange args) {
        const layout::Cell &layout = layouts.box(list.data).cell(list.shape.cons);
        Value cons = args[0];
        unsigned element = list.shape.element;
        SmallVector<Value> head =
            runtime.load(after, l, cons, cellAlignment(), layout.fields[element]);
        SmallVector<Value> rest =
            runtime.load(after, l, cons, cellAlignment(), layout.fields[1 - element]);
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
  return runtime.call(b, loc, idr::runtime::helper::strAlloc, ValueRange{bytes, scalars})
      .getResult();
}

// What writing one element of a list writes: a character as put_char does,
// a string as put_str does, each by its op's own runtime function.
template <typename OpT>
const idr::runtime::Function &elementOutput() {
  if constexpr (std::is_same_v<OpT, StrPackOp>)
    return idr::runtime::Abi<IoPutCharOp>::entry;
  else
    return idr::runtime::Abi<IoPutStrOp>::entry;
}

// pack and concat walk a list the same way: once for the bytes and the
// scalar values, then once to write each element after the last. A
// character's sizes and a string's are the runtime's. Where the string's
// one use writes it, the walk writes each element there instead, and
// neither the string nor its output is left.
template <typename OpT>
struct LowerStringOfList : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    constexpr bool packing = std::is_same_v<OpT, StrPackOp>;
    Location loc = op.getLoc();
    List list = listOf(op.getList().getType());
    Value cell = adaptor.getList().front();
    if (op->hasOneUse())
      if (auto output = dyn_cast<IoPutStrOp>(*op->user_begin())) {
        rewriter.setInsertionPoint(output);
        walk(rewriter, output.getLoc(), this->layouts, this->runtime, list, cell, {},
             [&](OpBuilder &b, Location l, ValueRange head, ValueRange) {
               this->runtime.call(b, l, elementOutput<OpT>(), head.front());
               return SmallVector<Value>{};
             });
        rewriter.eraseOp(output);
        rewriter.eraseOp(op);
        return success();
      }
    Value zero = arith::ConstantIntOp::create(rewriter, loc, 0, 64);
    SmallVector<Value> counts =
        walk(rewriter, loc, this->layouts, this->runtime, list, cell, {zero, zero},
             [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
               Value item = head.front();
               auto count = [&](const idr::runtime::Function &function) {
                 return this->runtime.call(b, l, function, item).getResult();
               };
               Value bytes, scalars;
               if constexpr (packing) {
                 bytes = arith::AddIOp::create(b, l, carried[0],
                                               count(idr::runtime::Abi<StrScalarBytesOp>::entry));
                 Value one = arith::ConstantIntOp::create(b, l, 1, 64);
                 scalars = arith::AddIOp::create(b, l, carried[1], one);
               } else {
                 bytes = arith::AddIOp::create(b, l, carried[0],
                                               count(idr::runtime::Abi<StrBytesLengthOp>::entry));
                 scalars = arith::AddIOp::create(b, l, carried[1],
                                                 count(idr::runtime::Abi<StrLengthOp>::entry));
               }
               return SmallVector<Value>{bytes, scalars};
             });
    Value s = allocate(rewriter, loc, this->runtime, counts[0], counts[1]);
    walk(rewriter, loc, this->layouts, this->runtime, list, cell, {zero},
         [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
           const idr::runtime::Function &put =
               packing ? idr::runtime::helper::strPutChar : idr::runtime::helper::strPutStr;
           Value next =
               this->runtime.call(b, l, put, ValueRange{s, carried[0], head.front()}).getResult();
           return SmallVector<Value>{next};
         });
    rewriter.replaceOpWithMultiple(op, {{s}});
    return success();
  }
};

} // namespace

// The string builders over lists.
void populateStringPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                            const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerStringOfList<StrPackOp>, LowerStringOfList<StrConcatOp>>(
      converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
