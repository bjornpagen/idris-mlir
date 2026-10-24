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
// live. Writing a list's pack or concat, its one reader, is the composition
// the lowering emits with no string at all: one walk, each element written
// as idr.io.put_char or idr.io.put_str writes it, where the output stands.
// What each builder does with one element, a runtime function for each
// step, is the specification's table (ListElement).
// Writing a number's show, its one reader, is the show's writer called
// there (ShownOutput): the runtime's put and show share the formatter, so
// the text is formatted into the output and no string is made.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Counting/Traits.h"
#include "idr/IR/Effects/Declared.h"
#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Traits.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Lower/Lower.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/Runtime.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Transforms/DialectConversion.h"
#include "llvm/ADT/STLExtras.h"

#include <concepts>
#include <cstdint>
#include <optional>

// Each show's writer: ShownOutput. What each builder over a list does with
// one element: ListElement.
#include "idr/IR/Generated/ListElement.h.inc"
#include "idr/IR/Generated/ShownOutput.h.inc"

using namespace mlir;

namespace idr::conversion {

namespace {

// Whether something may give up a value of `type` before a later reader
// reads it: its count, or its lifetime's end, where it holds references one
// of them frees. A value that holds none, and static data, are never freed.
enum class Lives : unsigned char { Always, UntilGivenUp };

Lives livesOf(Type type) {
  std::optional<Hold> hold = holdOf(type);
  if (!hold)
    return Lives::Always;
  switch (hold->release()) {
  case Release::Static:
    return Lives::Always;
  case Release::Counted:
  case Release::Scoped:
    return Lives::UntilGivenUp;
  }
  return Lives::UntilGivenUp;
}

// The one output of the string `maker` makes, where every other use of the
// string gives it up and the output may still read what the maker read: a
// string made only to be written, which the output writes from the maker's
// operands instead. Each use is what its op declares of its first operand,
// so no op is named: the output eliminates the string, writing it being all
// it does with it (EliminatesOperand: a string's output, as raising reads
// it), and a use that ends the string's owner only gives its reference up,
// a string having no fields to move out (EndsOwner), so it goes with the
// string. The string as any other operand is handed on, as into a match's
// case. An operand something may give up is still held where the output
// follows the maker in its block and nothing between them uses it: only a
// use gives up a count, and a lifetime ends at the end of its region, which
// holds both or neither. None where anything else reads the string, or an
// operand may be gone by the output.
Operation *writtenOnly(Operation *maker) {
  Operation *output = nullptr;
  for (OpOperand &use : maker->getResult(0).getUses()) {
    Operation *user = use.getOwner();
    if (use.getOperandNumber() != 0)
      return nullptr;
    if (user->hasTrait<EndsOwner>())
      continue;
    if (!user->hasTrait<EliminatesOperand>() || output)
      return nullptr;
    output = user;
  }
  if (!output)
    return nullptr;
  Block *block = maker->getBlock();
  for (Value operand : maker->getOperands()) {
    if (livesOf(operand.getType()) == Lives::Always)
      continue;
    if (output->getBlock() != block)
      return nullptr;
    for (Operation *user : operand.getUsers())
      if (Operation *at = block->findAncestorOpInBlock(*user);
          at && maker->isBeforeInBlock(at) && at->isBeforeInBlock(output))
        return nullptr;
  }
  return output;
}

// The string `s` is no longer made: its output and every drop of it go.
void eraseReaders(ConversionPatternRewriter &rewriter, Value s) {
  for (Operation *user : llvm::make_early_inc_range(s.getUsers()))
    rewriter.eraseOp(user);
}

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
template <class S>
concept Step = requires(S &step, OpBuilder &b, Location loc, ValueRange head,
                        ValueRange carried) {
  { step(b, loc, head, carried) } -> std::same_as<SmallVector<Value>>;
};

// Walks the list at `cell` while it is a cons, carrying `inits` through
// `step`; gives the carried values at the nil.
template <Step S>
SmallVector<Value> walk(OpBuilder &b, Location loc, const Layouts &layouts, Runtime &runtime,
                        const List &list, Value cell, ValueRange inits, S &&step) {
  SmallVector<Type> types{cell.getType()};
  SmallVector<Value> operands{cell};
  for (Value init : inits) {
    types.push_back(init.getType());
    operands.push_back(init);
  }
  auto loop = scf::WhileOp::create(
      b, loc, types, operands,
      [&](OpBuilder &before, Location l, ValueRange args) {
        Value tag = runtime.loadTag(before, l, args[0], list.data, Contents::Stays);
        Value consTag = arith::ConstantIntOp::create(
            before, l, static_cast<uint32_t>(list.shape.cons), 64);
        Value isCons = arith::CmpIOp::create(before, l, arith::CmpIPredicate::eq, tag, consTag);
        scf::ConditionOp::create(before, l, isCons, args);
      },
      [&](OpBuilder &after, Location l, ValueRange args) {
        const layout::Cell &layout = layouts.cells(list.data).cell(list.shape.cons);
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

// The scalar values of one element: the count every element has, as a
// character's one, or the runtime's count of the element's own, as a
// string's length.
Value scalarsOf(OpBuilder &b, Location loc, const Runtime &, std::int64_t each, Value) {
  return arith::ConstantIntOp::create(b, loc, each, 64);
}
Value scalarsOf(OpBuilder &b, Location loc, const Runtime &runtime,
                const idr::runtime::Function &count, Value element) {
  return runtime.call(b, loc, count, element).getResult();
}

// pack and concat walk a list the same way: once for the bytes and the
// scalar values, then once to write each element after the last. What each
// step does with an element is its builder's table (ListElement): the
// runtime's sizes of a character or a string, and its writing of one into
// the string or to the output. Where the string is made only to be
// written, the walk writes each element there instead, and neither the
// string, its output nor its drops are left.
template <typename OpT>
struct LowerStringOfList : IdrPattern<OpT> {
  using IdrPattern<OpT>::IdrPattern;
  using Element = ListElement<OpT>;
  LogicalResult matchAndRewrite(OpT op, typename IdrPattern<OpT>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Location loc = op.getLoc();
    List list = listOf(op.getList().getType());
    Value cell = adaptor.getList().front();
    if (Operation *output = writtenOnly(op)) {
      rewriter.setInsertionPoint(output);
      walk(rewriter, output->getLoc(), this->layouts, this->runtime, list, cell, {},
           [&](OpBuilder &b, Location l, ValueRange head, ValueRange) {
             this->runtime.call(b, l, Element::output, head.front());
             return SmallVector<Value>{};
           });
      eraseReaders(rewriter, op.getResult());
      rewriter.eraseOp(op);
      return success();
    }
    Value zero = arith::ConstantIntOp::create(rewriter, loc, 0, 64);
    SmallVector<Value> counts =
        walk(rewriter, loc, this->layouts, this->runtime, list, cell, {zero, zero},
             [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
               Value item = head.front();
               Value bytes = arith::AddIOp::create(
                   b, l, carried[0], this->runtime.call(b, l, Element::bytes, item).getResult());
               Value scalars = arith::AddIOp::create(
                   b, l, carried[1], scalarsOf(b, l, this->runtime, Element::scalars, item));
               return SmallVector<Value>{bytes, scalars};
             });
    Value s = allocate(rewriter, loc, this->runtime, counts[0], counts[1]);
    walk(rewriter, loc, this->layouts, this->runtime, list, cell, {zero},
         [&](OpBuilder &b, Location l, ValueRange head, ValueRange carried) {
           Value next = this->runtime
                            .call(b, l, Element::into, ValueRange{s, carried[0], head.front()})
                            .getResult();
           return SmallVector<Value>{next};
         });
    rewriter.replaceOpWithMultiple(op, {{s}});
    return success();
  }
};

// A show whose string is made only to be written: its writer writes the
// show's text where the output stood, and neither the string nor its drops
// are left. Any other show is its runtime call's, which this pattern, tried
// first, leaves it to.
template <typename ShowOp>
struct LowerShownOutput : IdrPattern<ShowOp> {
  LowerShownOutput(const TypeConverter &converter, MLIRContext *ctx, const Layouts &layouts,
                   Runtime &runtime)
      : IdrPattern<ShowOp>(converter, ctx, layouts, runtime, ownLowering),
        facts(callFacts(ctx, effects::bound<IoPutStrOp>().row())) {}

  // What the writer does, which is what the output it stands for does:
  // made once, with the pattern.
  CallFacts facts;

  LogicalResult matchAndRewrite(ShowOp op, typename IdrPattern<ShowOp>::OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    Operation *output = writtenOnly(op);
    if (!output)
      return rewriter.notifyMatchFailure(op, "its string is not made only to be written");
    rewriter.setInsertionPoint(output);
    tellCall(this->runtime.call(rewriter, op, ShownOutput<ShowOp>::writer, adaptor.getOperands()),
             facts);
    eraseReaders(rewriter, op.getResult());
    rewriter.eraseOp(op);
    return success();
  }
};

// One LowerStringOfList rooted at each builder of `Builders`.
template <typename... Builders>
void addStringsOfLists(RewritePatternSet &patterns, const TypeConverter &converter,
                       const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerStringOfList<Builders>...>(converter, patterns.getContext(), layouts, runtime);
}

// One LowerShownOutput rooted at each show of `Shows`.
template <typename... Shows>
void addShownOutputs(RewritePatternSet &patterns, const TypeConverter &converter,
                     const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerShownOutput<Shows>...>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace

// The string builders over lists, and the output of a show.
void populateStringPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                            const Layouts &layouts, Runtime &runtime) {
  addStringsOfLists<
#define GET_LIST_ELEMENT_LIST
#include "idr/IR/Generated/ListElement.h.inc"
      >(patterns, converter, layouts, runtime);
  addShownOutputs<
#define GET_SHOWN_OUTPUT_LIST
#include "idr/IR/Generated/ShownOutput.h.inc"
      >(patterns, converter, layouts, runtime);
}

} // namespace idr::conversion
