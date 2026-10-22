// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A value re-packed from one layout into another. Inline or in a cell is
// layout, computed from a type's indices when the type is made: a closed
// application held in place is its own unfolding, over the fields its
// indices determine, and every other value of a member is laid out as the
// member at an unknown index, at its constructors' own fields. So one value
// has two layouts where a reindex forgets or learns a closed index, where
// a field's type at its value's application is closed and its slot, at
// the constructor's own fields, is not, and where an index.assume rebinds
// a value. Between them the value is re-packed: a numeral of a fixed width
// made a natural or made of one; an array whose elements lay out apart
// copied element by element into a fresh array; and a value of any other
// family taken apart at each constructor both types leave possible, its
// fields re-packed in turn, and built again, in place or in a cell. A cell
// is allocated as every counted cell is, and an atom of a family in cells
// is the static cell of its constructor (idr-lower-statics makes every
// one). Where the two layouts agree the value is its words, as they are.
// No layout is refused.
//
// What the value holds goes on to the result. A cell taken apart gives its
// fields to the result: shared, each field gains a reference and the cell
// loses one; held alone, as its grade claims, its memory is given back with
// no count read; read where its owner keeps it, or scoped or static,
// nothing is counted, and the result reads what it read. A value in place
// moves its words. A numeral read into a fixed width keeps no reference, so
// a natural it was read from that may be a big loses its own. A re-pack
// that builds a cell or an array gives a fresh counted value, claimed
// unique, whatever the operand's hold, so counting frees it as any fresh
// cell: everything it holds is its own, so an operand it does not own
// gains its own references first, and is then taken as one it holds among
// others.
//
// The re-pack descends only where a value in place is unfolded, whose
// depth the shape budget of the layouts bounds, and into an array's
// element type, never the input; it reads only types the layouts made, so
// no lowering worker makes one.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Grades.h"
#include "idr/Conversion/Arrays.h"
#include "idr/Conversion/Elements.h"
#include "idr/Conversion/IdrPattern.h"
#include "idr/Conversion/Patterns.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Conversion/Words.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "llvm/ADT/STLExtras.h"

// The runtime's C ABI: the small Integer word's range.
#include "idris_rt.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The re-pack of one value, its builder at the point it goes.
struct Repacker {
  OpBuilder &b;
  Location loc;
  const Layouts &layouts;
  Runtime &runtime;

  SmallVector<Type> typesOf(Type type) const {
    return llvm::map_to_vector(layouts.components(type),
                               [](const layout::Component &c) { return c.type; });
  }

  // The constructors a value may hold at both types.
  static SmallVector<Tag> commonTags(DataType source, DataType target) {
    SmallVector<Tag> tags;
    for (Tag tag : source.possibleTags())
      if (target.possibleTags().contains(tag))
        tags.push_back(tag);
    return tags;
  }

  // The same words where the two types are, as the reindex's verifier
  // reads them. Only data types and arrays lay out apart under one family:
  // a natural is one word at any index.
  SmallVector<Value> of(Type from, Type to, ValueRange values, Takes takes) const {
    if (families::layoutMatch(from, to) == LayoutMatch::SameLayout)
      return SmallVector<Value>(values);
    if (auto source = dyn_cast<MemRefType>(from))
      return array(source, cast<MemRefType>(to), values, takes);
    auto source = cast<DataType>(from);
    auto target = cast<DataType>(to);
    if (families::isNumber(source.layout()))
      return numeral(source, target, values, takes.own);
    SmallVector<Tag> tags = commonTags(source, target);
    // A type no constructor inhabits holds no value to re-pack.
    if (tags.empty())
      return llvm::map_to_vector(typesOf(to), [&](Type type) -> Value {
        return ub::PoisonOp::create(b, loc, type);
      });
    if (tags.size() == 1)
      return built(source, target, tags.front(), values, takes);
    // Each constructor, chosen by the value's tag: its tag word in place,
    // its header in a cell.
    Value tag = source.layout() == Layout::InPlace
                    ? Value(arith::ExtUIOp::create(b, loc, b.getI64Type(), values.front()))
                    : runtime.loadTag(b, loc, values.front(), source, contentsOf(source));
    Value index = arith::IndexCastOp::create(b, loc, b.getIndexType(), tag);
    SmallVector<int64_t> cases;
    for (Tag each : ArrayRef(tags).drop_back())
      cases.push_back(static_cast<uint32_t>(each));
    auto choose = scf::IndexSwitchOp::create(b, loc, typesOf(to), index, cases,
                                             static_cast<unsigned>(cases.size()));
    auto branch = [&](Region &region, Tag known) {
      OpBuilder::InsertionGuard guard(b);
      b.createBlock(&region);
      scf::YieldOp::create(b, loc, built(source, target, known, values, takes));
    };
    for (auto [region, known] :
         llvm::zip_equal(choose.getCaseRegions(), ArrayRef(tags).drop_back()))
      branch(region, known);
    branch(choose.getDefaultRegion(), tags.back());
    return SmallVector<Value>(choose.getResults());
  }

  // A numeral at the other side of its bound, closed on one side and open
  // on the other: a fixed width made a natural, or a natural made a fixed
  // width, as the numerals' own conversions hold each width. A natural read
  // into a width past the small range may have been a big, whose reference
  // the number no longer holds.
  SmallVector<Value> numeral(DataType source, DataType target, ValueRange values,
                             Taken taken) const {
    Value word = values.front();
    if (source.layout() != Layout::Natural)
      return {naturalOf(b, loc, runtime, layouts.components(source).front(), word)};
    Value number = numeralOf(b, loc, runtime, layouts.components(target).front(), word);
    std::optional<uint64_t> bound = target.numeralBound();
    if (taken != Taken::Borrowed && bound && *bound > static_cast<uint64_t>(IDRIS_RT_SMALL_MAX))
      runtime.dec(b, loc, layouts.components(source), values);
    return {number};
  }

  // An array whose elements lay out apart: a fresh array of the same sizes,
  // in row-major order, each element read, given a reference of its own and
  // re-packed into it, and the operand's array then given up, which its
  // elements' own references balance.
  SmallVector<Value> array(MemRefType source, MemRefType target, ValueRange values,
                           Takes takes) const {
    Type from = unrestricted(source.getElementType());
    Type to = unrestricted(target.getElementType());
    const layout::Element &read = layouts.element(from);
    const layout::Element &write = layouts.element(to);
    Descriptor given = unpack(b, loc, source, values);
    Descriptor fresh{newCell(b, loc, runtime, countOf(b, loc, given.sizes), write),
                     b.getI64IntegerAttr(0), given.sizes, {}};
    fresh.strides.resize(given.sizes.size());
    Value stride = i64Constant(b, loc, 1);
    for (size_t at = given.sizes.size(); at-- > 0;) {
      fresh.strides[at] = stride;
      stride = arith::MulIOp::create(b, loc, stride, asWord(b, loc, given.sizes[at]));
    }
    SmallVector<Value> made = pack(b, loc, target, fresh);
    {
      OpBuilder::InsertionGuard guard(b);
      Value zero = arith::ConstantIndexOp::create(b, loc, 0);
      Value one = arith::ConstantIndexOp::create(b, loc, 1);
      SmallVector<Value> indices;
      for (OpFoldResult size : given.sizes) {
        auto loop = scf::ForOp::create(b, loc, zero, asIndex(b, loc, size), one);
        b.setInsertionPointToStart(loop.getBody());
        indices.push_back(loop.getInductionVar());
      }
      SmallVector<Value> element = readElement(
          b, loc, runtime, elementAddress(b, loc, runtime, source, values, read, indices), read);
      runtime.inc(b, loc, layouts.components(from), element);
      placeElement(b, loc, runtime, elementAddress(b, loc, runtime, target, made, write, indices),
                   write, of(from, to, element, {Taken::Shared, Taken::Shared}));
    }
    if (takes.own != Taken::Borrowed)
      dropValue(b, loc, runtime, layouts, source, values);
    return made;
  }

  // Constructor `tag` of `values` taken apart at `source`'s layout, its
  // fields re-packed, and built at `target`'s.
  SmallVector<Value> built(DataType source, DataType target, Tag tag, ValueRange values,
                           Takes takes) const {
    ArrayRef<Type> from = layouts.fieldTypes(source, tag);
    ArrayRef<Type> to = layouts.fieldTypes(target, tag);
    SmallVector<SmallVector<Value>> parts;
    if (source.layout() == Layout::InPlace) {
      for (unsigned index = 0; index < from.size(); ++index)
        parts.push_back(unboxedField(layouts.sum(source), values, tag, index));
    } else {
      Value cell = values.front();
      const layout::Cell &shape = layouts.cells(source).cell(tag);
      for (ArrayRef<layout::Slot> slots : shape.fields)
        parts.push_back(runtime.load(b, loc, cell, cellAlignment(), slots, contentsOf(source)));
      // An atom is the static cell of its constructor, which nothing frees.
      if (!shape.fields.empty())
        release(cell, from, parts, takes.own);
    }
    Takes inner{takes.reached, takes.reached};
    SmallVector<SmallVector<Value>> fields;
    for (auto [part, a, z] : llvm::zip_equal(parts, from, to))
      fields.push_back(of(unrestricted(a), unrestricted(z), part, inner));
    SmallVector<ValueRange> given(fields.begin(), fields.end());
    if (target.layout() == Layout::InPlace)
      return unboxedSum(b, loc, layouts.sum(target), tag, given);
    if (to.empty()) {
      MLIRContext *ctx = b.getContext();
      auto atom = ConAttr::get(ctx, target.refinedTo(tag, {}), ArrayAttr::get(ctx, {}));
      return constantComponents(b, loc, layouts, atom, target);
    }
    const layout::Cell &shape = layouts.cells(target).cell(tag);
    Value cell = runtime.allocate(b, loc, shape);
    for (auto [slots, field] : llvm::zip_equal(shape.fields, given))
      runtime.store(b, loc, cell, cellAlignment(), slots, field);
    return {cell};
  }

  // A cell whose fields were read out, given up as `taken` says.
  void release(Value cell, ArrayRef<Type> from, ArrayRef<SmallVector<Value>> parts,
               Taken taken) const {
    switch (taken) {
    case Taken::Shared:
      for (auto [type, part] : llvm::zip_equal(from, parts))
        runtime.inc(b, loc, layouts.components(type), part);
      runtime.dec(b, loc, layout::Word::Cell, cell);
      return;
    case Taken::Alone:
      runtime.call(b, loc, idr::runtime::helper::freeToken, cell);
      return;
    case Taken::Borrowed:
      return;
    }
  }
};

// The same words where the reindex is free, which its two types answer;
// else its operand re-packed, given on whole.
struct LowerReindex : IdrPattern<DataReindexOp> {
  using IdrPattern::IdrPattern;
  LogicalResult matchAndRewrite(DataReindexOp op, OneToNOpAdaptor adaptor,
                                ConversionPatternRewriter &rewriter) const override {
    ValueRange value = adaptor.getValue();
    if (op.isFree()) {
      rewriter.replaceOpWithMultiple(op, {SmallVector<Value>(value)});
      return success();
    }
    Type from = op.getValue().getType();
    rewriter.replaceOpWithMultiple(
        op, {repack(rewriter, op.getLoc(), layouts, runtime, from, op.getType(), value,
                    takesOf(from))});
    return success();
  }
};

} // namespace

Takes takesOf(Type type) {
  if (!freedBy(type, Release::Counted))
    return readInPlace;
  if (claims(type, Unique::Deep))
    return {Taken::Alone, Taken::Alone};
  if (claims(type, Unique::Self))
    return {Taken::Alone, Taken::Shared};
  return {Taken::Shared, Taken::Shared};
}

SmallVector<Value> repack(OpBuilder &b, Location loc, const Layouts &layouts, Runtime &runtime,
                          Type from, Type to, ValueRange values, Takes takes) {
  Repacker repacker{b, loc, layouts, runtime};
  Type source = unrestricted(from);
  Type target = unrestricted(to);
  // Whether it builds is the one answer the reindex's verifier reads too,
  // over the field types the layouts made.
  if (takes.own == Taken::Borrowed &&
      families::builds(source, target,
                       [&](DataType type, Tag tag) { return layouts.fieldTypes(type, tag); })) {
    runtime.inc(b, loc, layouts.components(source), values);
    takes = {Taken::Shared, Taken::Shared};
  }
  return repacker.of(source, target, values, takes);
}

SmallVector<SmallVector<Value>> intoSlots(OpBuilder &b, Location loc, const Layouts &layouts,
                                          Runtime &runtime, DataType data, Tag tag,
                                          ValueRange operands, ArrayRef<ValueRange> given) {
  SmallVector<SmallVector<Value>> fields;
  for (auto [operand, values, slot] :
       llvm::zip_equal(operands, given, layouts.fieldTypes(data, tag)))
    fields.push_back(repack(b, loc, layouts, runtime, operand.getType(), slot, values,
                            takesOf(operand.getType())));
  return fields;
}

void populateReindexPatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                             const Layouts &layouts, Runtime &runtime) {
  patterns.add<LowerReindex>(converter, patterns.getContext(), layouts, runtime);
}

} // namespace idr::conversion
