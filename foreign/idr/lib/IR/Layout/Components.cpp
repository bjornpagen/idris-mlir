// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime components of a value type, each with the kind of word it
// is; the plan of a memref's descriptor; and the slots of a data type held
// in place, as its type laid them out when it was made.
//
// What each type is at run time is said once, in one fold over the
// dialect's types, as the list its specification generates: a type the
// specification adds has no case there until one is written, and the fold
// does not compile. The fold makes no type, since a data type asks for the
// words its fields take while it is being made; a data type's own words
// are the ones it computed then, and the components name the word types
// the words describe, so every count of them is one count.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Layout/SlotPlan.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Support/Match.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#include <functional>
#include <optional>
#include <string>
#include <type_traits>
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

//===----------------------------------------------------------------------===//
// What a value of each type is at run time
//===----------------------------------------------------------------------===//

// One pointer, of a kind of word.
struct Pointer {
  Word word;
};
// One integer `bits` wide: a big's word.
struct Integer {
  unsigned bits;
  Word word;
};
// A builtin scalar or vector: the value is its own word, and no count is
// kept of it.
struct Itself {
  Type type;
};
// No word: a lifetime whose kind is erased at run time.
struct NoWord {};
// One address no count is kept of per component of a value of `of`, each
// that component's slot in the place it is written (a destination).
struct Addresses {
  Type of;
};
// An array's cell and what of its descriptor its type leaves to the value.
struct Descriptor {
  ShapedType array;
};
// A data type: the words it computed when it was made.
struct Held {
  DataType data;
};

using Words = std::variant<Pointer, Integer, Itself, NoWord, Addresses, Descriptor, Held>;

// Every type of the dialect, as its specification generates them.
template <class... Ts>
struct TypeList {};
using DialectTypes = TypeList<
#define GET_TYPEDEF_LIST
#include "idr/IR/IdrTypes.cpp.inc"
    >;

// `type`, a type of the dialect, handed to the one case that takes its
// class: one compare per class, and every class of the list must have a
// case giving its words, or this does not compile.
template <class C, class... Ts>
Words foldDialect(Type type, TypeList<Ts...>, C &&cases) {
  static_assert((std::is_invocable_r_v<Words, C &, Ts> && ...),
                "every type of the dialect says what its values are at run time");
  std::optional<Words> out;
  (void)((isa<Ts>(type) && (out.emplace(std::invoke(cases, cast<Ts>(type))), true)) || ...);
  return *std::move(out);
}

// The words of a value of `type`, held at `hold` when a grade around it
// says so. A cell before its init, a package and a frame stack are each
// used once by their types, an address no count is kept of; a reuse token
// may be null unless its grade says it holds its cell; a string, a closure
// and a suspension are a cell's address; a big and a natural are a big's
// word, a small integer or a cell's address; a destination is an address
// per component of what it takes; a lifetime is what its kind lowers to;
// a data type is the words it computed. An upstream array is its cell and
// its descriptor, another upstream type that holds a reference a cell's
// address, and any other a scalar.
Words wordsOf(Type type, std::optional<Hold> hold = std::nullopt) {
  if (isa<IdrDialect>(type.getDialect()))
    return foldDialect(
        type, DialectTypes{},
        Cases{
            [](CellType) -> Words { return Pointer{Word::Uncounted}; },
            [&](TokenType) -> Words {
              return Pointer{hold && hold->claims(Unique::Deep) ? Word::Cell : Word::MaybeCell};
            },
            [](GradedType graded) -> Words {
              return wordsOf(graded.getCarrier(), graded.getHold());
            },
            [](DestType dest) -> Words { return Addresses{dest.getValue()}; },
            [](LifetimeType lifetime) -> Words {
              if (lifetime.getKind().lowered() == Lowered::NoValue)
                return NoWord{};
              return Pointer{Word::Uncounted};
            },
            [](LifetimePackageType) -> Words { return Pointer{Word::Uncounted}; },
            [](StrType) -> Words { return Pointer{Word::Cell}; },
            [](BigType) -> Words { return Integer{64, Word::Big}; },
            [](NatType) -> Words { return Integer{64, Word::Big}; },
            [](FnType) -> Words { return Pointer{Word::Cell}; },
            [](LazyType) -> Words { return Pointer{Word::Cell}; },
            [](DataType data) -> Words { return Held{data}; },
            // Essential: the dialect's types include one no value has. A
            // member of a group by position is read with its declaration,
            // whose readers take it as its member's data type, and the
            // function's scope walk refuses a value whose type names one.
            [](SelfType) -> Words {
              llvm::reportFatalInternalError(
                  "the run-time words of a member of a group by position, which only its "
                  "declaration names");
            },
        });
  if (isa<RankedTensorType, MemRefType>(type))
    return Descriptor{cast<ShapedType>(type)};
  if (holdsReferences(type))
    return Pointer{Word::Cell};
  return Itself{type};
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
  return match(
      wordsOf(type), [](Pointer) -> uint32_t { return 1; }, [](Integer) -> uint32_t { return 1; },
      [](Itself) -> uint32_t { return 1; }, [](NoWord) -> uint32_t { return 0; },
      [](Addresses places) -> uint32_t { return componentCount(places.of); },
      [](Descriptor descriptor) -> uint32_t {
        return 1 + DescriptorFields::of(descriptor.array).carried();
      },
      [](Held held) -> uint32_t { return held.data.components(); });
}

SmallVector<families::SlotWord> slotWordsOf(Type type) {
  using families::IntegerWord;
  using families::PointerWord;
  using families::ScalarWord;
  using families::SlotWord;
  using Out = SmallVector<SlotWord>;
  return match(
      wordsOf(type), [](Pointer one) -> Out { return {SlotWord{PointerWord{}, one.word}}; },
      [](Integer one) -> Out { return {SlotWord{IntegerWord{one.bits}, one.word}}; },
      // An integer the value is itself is the word any integer of its width
      // is, so the two share a slot.
      [](Itself one) -> Out {
        if (auto integer = dyn_cast<IntegerType>(one.type); integer && integer.isSignless())
          return {SlotWord{IntegerWord{integer.getWidth()}, Word::Uncounted}};
        return {SlotWord{ScalarWord{one.type}, Word::Uncounted}};
      },
      [](NoWord) -> Out { return {}; },
      [](Addresses places) -> Out {
        return Out(componentCount(places.of), SlotWord{PointerWord{}, Word::Uncounted});
      },
      [](Descriptor descriptor) -> Out {
        Out out{SlotWord{PointerWord{}, Word::Cell}};
        out.append(DescriptorFields::of(descriptor.array).carried(),
                   SlotWord{IntegerWord{64}, Word::Uncounted});
        return out;
      },
      [](Held held) -> Out { return families::flatWords(held.data.slots()); });
}

Reach reachOf(Type type) {
  Type value = unrestricted(type);
  if (auto data = dyn_cast<DataType>(value))
    return data.boundsReach() ? Reach::Bounded : Reach::Unbounded;
  return holdsReferences(value) ? Reach::Unbounded : Reach::Bounded;
}

} // namespace idr::layout

// One type at two grades is the same words; two data types are as their
// layout facts say; two arrays are where their elements are and their
// descriptors' words agree; any other two where their words agree. Makes
// no type: the lowering asks it of every field it reads.
idr::LayoutMatch idr::families::layoutMatch(Type from, Type to) {
  Type fromValue = unrestricted(from);
  Type toValue = unrestricted(to);
  if (fromValue == toValue)
    return LayoutMatch::SameLayout;
  auto fromData = dyn_cast<DataType>(fromValue);
  auto toData = dyn_cast<DataType>(toValue);
  if (fromData && toData)
    return fromData.layoutMatch(toData);
  auto fromArray = dyn_cast<MemRefType>(fromValue);
  auto toArray = dyn_cast<MemRefType>(toValue);
  if (fromArray && toArray &&
      layoutMatch(fromArray.getElementType(), toArray.getElementType()) == LayoutMatch::OtherLayout)
    return LayoutMatch::OtherLayout;
  return layout::slotWordsOf(fromValue) == layout::slotWordsOf(toValue) ? LayoutMatch::SameLayout
                                                                       : LayoutMatch::OtherLayout;
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
