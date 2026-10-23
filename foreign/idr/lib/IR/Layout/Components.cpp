// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime components of a value type, each with the kind of word it
// is; the plan of a memref's descriptor; and the slots of a data type held
// in place, as its type laid them out when it was made.
//
// What each type is at run time is its own answer, the run-time words its
// value facts give (runTimeWordsOf), which the specification declares and
// each type defines: a type the specification adds answers, or does not
// build. Asking makes no type, since a data type asks for the words its
// fields take while it is being made; a data type's own words are the ones
// it computed then, and the components name the word types the words
// describe, so every count of them is one count.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Layout/SlotPlan.h"
#include "idr/IR/Symbols.h"
#include "idr/Support/Match.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#include <optional>
#include <string>
#include <utility>
#include <variant>

using namespace mlir;

namespace idr::layout {

namespace {

DescriptorField fieldOf(int64_t value) {
  if (ShapedType::isDynamic(value))
    return Carried{};
  return Fixed{value};
}

unsigned carriedIn(ArrayRef<DescriptorField> fields) {
  return static_cast<unsigned>(llvm::count_if(fields, [](const DescriptorField &field) {
    return match(field, [](Carried) { return true; }, [](Fixed) { return false; });
  }));
}

} // namespace

unsigned DescriptorFields::carried() const {
  return carriedIn(offset) + carriedIn(sizes) + (strides ? carriedIn(*strides) : 0u);
}

DescriptorFields DescriptorFields::of(ShapedType type) {
  DescriptorFields fields{Fixed{0}, llvm::map_to_vector(type.getShape(), fieldOf), std::nullopt};
  auto memref = dyn_cast<MemRefType>(type);
  // A tensor and an identity layout carry no stride: the sizes say them.
  if (!memref || memref.getLayout().isIdentity())
    return fields;
  SmallVector<int64_t> steps;
  int64_t start;
  if (failed(memref.getStridesAndOffset(steps, start))) {
    std::string text;
    llvm::raw_string_ostream(text) << memref;
    llvm::reportFatalInternalError(llvm::Twine("the layout of ") + text +
                                   " has no strides, and the program's verifier refuses a memref "
                                   "value whose layout is not strided");
  }
  fields.offset = fieldOf(start);
  fields.strides = llvm::map_to_vector(steps, fieldOf);
  return fields;
}

uint32_t componentCount(Type type) {
  namespace words = run_time_words;
  return match(
      runTimeWordsOf(type), [](words::Pointer) -> uint32_t { return 1; },
      [](words::Integer) -> uint32_t { return 1; }, [](words::Itself) -> uint32_t { return 1; },
      [](words::NoWord) -> uint32_t { return 0; },
      [](words::Addresses places) -> uint32_t { return componentCount(places.of); },
      [](words::Descriptor descriptor) -> uint32_t {
        return 1 + DescriptorFields::of(descriptor.array).carried();
      },
      [](words::Held held) -> uint32_t { return held.data.get().components(); });
}

SmallVector<families::SlotWord> slotWordsOf(Type type) {
  using families::IntegerWord;
  using families::PointerWord;
  using families::ScalarWord;
  using families::SlotWord;
  using Out = SmallVector<SlotWord>;
  namespace words = run_time_words;
  return match(
      runTimeWordsOf(type),
      [](words::Pointer one) -> Out { return {SlotWord{PointerWord{}, one.word}}; },
      [](words::Integer one) -> Out { return {SlotWord{IntegerWord{one.bits}, one.word}}; },
      // An integer the value is itself is the word any integer of its width
      // is, so the two share a slot.
      [](words::Itself one) -> Out {
        if (auto integer = dyn_cast<IntegerType>(one.type); integer && integer.isSignless())
          return {SlotWord{IntegerWord{integer.getWidth()}, Word::Uncounted}};
        return {SlotWord{ScalarWord{one.type}, Word::Uncounted}};
      },
      [](words::NoWord) -> Out { return {}; },
      [](words::Addresses places) -> Out {
        return Out(componentCount(places.of), SlotWord{PointerWord{}, Word::Uncounted});
      },
      [](words::Descriptor descriptor) -> Out {
        Out out{SlotWord{PointerWord{}, Word::Cell}};
        out.append(DescriptorFields::of(descriptor.array).carried(),
                   SlotWord{IntegerWord{64}, Word::Uncounted});
        return out;
      },
      [](words::Held held) -> Out { return families::flatWords(held.data.get().slots()); });
}

Reach reachOf(Type type) {
  if (DataType data = dataTypeOf(type))
    return data.boundsReach() ? Reach::Bounded : Reach::Unbounded;
  return holdsReferences(unrestricted(type)) ? Reach::Unbounded : Reach::Bounded;
}

} // namespace idr::layout

namespace {

// Both types as upstream's class `T`, or neither: a pair of one class is
// one test of the pair, never one per side.
template <typename T>
std::optional<std::pair<T, T>> pairOf(Type from, Type to) {
  auto first = dyn_cast<T>(from);
  auto second = dyn_cast<T>(to);
  if (!first || !second)
    return std::nullopt;
  return std::pair(first, second);
}

} // namespace

// One type at two grades is the same words; two data types are as their
// layout facts say; two arrays, upstream's memrefs, are where their
// elements are and their descriptors' words agree; any other two where
// their words agree. Makes no type: the lowering asks it of every field it
// reads.
idr::LayoutMatch idr::families::layoutMatch(Type from, Type to) {
  Type fromValue = unrestricted(from);
  Type toValue = unrestricted(to);
  if (fromValue == toValue)
    return LayoutMatch::SameLayout;
  DataType fromData = dataTypeOf(fromValue);
  DataType toData = dataTypeOf(toValue);
  if (fromData && toData)
    return fromData.layoutMatch(toData);
  if (std::optional<std::pair<MemRefType, MemRefType>> arrays =
          pairOf<MemRefType>(fromValue, toValue);
      arrays && layoutMatch(arrays->first.getElementType(), arrays->second.getElementType()) ==
                    LayoutMatch::OtherLayout)
    return LayoutMatch::OtherLayout;
  return layout::slotWordsOf(fromValue) == layout::slotWordsOf(toValue) ? LayoutMatch::SameLayout
                                                                       : LayoutMatch::OtherLayout;
}

idr::families::RepackStep idr::families::repackStep(Type from, Type to) {
  if (layoutMatch(from, to) == LayoutMatch::SameLayout)
    return RepackStep::BuildsNothing;
  if (isa<MemRefType>(unrestricted(to)))
    return RepackStep::Builds;
  DataType source = dataTypeOf(from);
  DataType target = dataTypeOf(to);
  if (!source || !target || isNumber(source.layout()))
    return RepackStep::BuildsNothing;
  return target.layout() == Layout::InPlace ? RepackStep::ByFields : RepackStep::Builds;
}

namespace idr {

namespace {

// A word as a component, its type made: a pointer is the target's, an
// integer its width's, a scalar itself.
layout::Component componentOf(MLIRContext *ctx, const families::SlotWord &word) {
  Type type = match(
      word.shape, [&](families::PointerWord) -> Type { return LLVM::LLVMPointerType::get(ctx); },
      [&](families::IntegerWord integer) -> Type { return IntegerType::get(ctx, integer.bits); },
      [](families::ScalarWord scalar) { return scalar.type; });
  return layout::Component{type, word.kind};
}

} // namespace

// The words the fold describes, with their types made, so a value's
// components are as many as layout::componentCount says.
SmallVector<layout::Component> Layouts::components(Type type) const {
  MLIRContext *ctx = type.getContext();
  return llvm::map_to_vector(layout::slotWordsOf(type), [&](const families::SlotWord &word) {
    return componentOf(ctx, word);
  });
}

// The slots its type laid out when it was made, with their types made.
layout::SumLayout Layouts::sumOf(DataType type) const {
  MLIRContext *ctx = type.getContext();
  const families::Slots &slots = type.unrefined().slots();
  layout::SumLayout out;
  if (slots.tag)
    out.tag = IntegerType::get(ctx, slots.tag->bits);
  out.words = llvm::map_to_vector(families::flatWords(slots), [&](const families::SlotWord &word) {
    return componentOf(ctx, word);
  });
  for (ArrayRef<ArrayRef<uint32_t>> perField : slots.fields) {
    SmallVector<SmallVector<unsigned>> &fields = out.fields.emplace_back();
    for (ArrayRef<uint32_t> positions : perField)
      fields.emplace_back(positions.begin(), positions.end());
  }
  return out;
}

} // namespace idr
