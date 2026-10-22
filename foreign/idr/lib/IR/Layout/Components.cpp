// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime components of a value type, each with the kind of word it
// is; the plan of a memref's descriptor; and the slots of a data type held
// in place, over the constructors its indices leave possible.
//
// What each type is at run time is said once, in one fold over the
// dialect's types, as the list its specification generates: a type the
// specification adds has no case there until one is written, and the fold
// does not compile. The fold makes no type, since a data type asks how many
// components its fields take while it is being made; the components name
// the word types it described.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Support/Match.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseMap.h"
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
// One integer `bits` wide: a big's word, or a number of a fixed width.
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
// A data type held in place: its slots.
struct Spread {
  DataType data;
};

using Words = std::variant<Pointer, Integer, Itself, NoWord, Addresses, Descriptor, Spread>;

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
// a data type is as its layout says. An upstream array is its cell and
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
            [](DataType data) -> Words {
              switch (data.layout()) {
              case Layout::FrameStack:
                return Pointer{Word::Uncounted};
              case Layout::Cell:
                return Pointer{Word::Cell};
              case Layout::Natural:
                return Integer{64, Word::Big};
              case Layout::InPlace:
                return Spread{data};
              case Layout::Word8:
              case Layout::Word16:
              case Layout::Word32:
              case Layout::Word64:
                return Integer{families::numberBits(data.layout()), Word::Uncounted};
              }
              llvm_unreachable("a data type's layout");
            },
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
      [](Spread spread) -> uint32_t { return spread.data.components(); });
}

Reach reachOf(Type type) {
  Type value = unrestricted(type);
  if (auto data = dyn_cast<DataType>(value))
    return data.boundsReach() ? Reach::Bounded : Reach::Unbounded;
  return holdsReferences(value) ? Reach::Unbounded : Reach::Bounded;
}

} // namespace idr::layout

namespace idr {

// The words the fold described, with their types made: a pointer is the
// target's, a big's word and a descriptor's carried field a 64-bit word.
SmallVector<layout::Component> Layouts::components(Type type) const {
  using layout::Component;
  using layout::Word;
  MLIRContext *ctx = type.getContext();
  Type pointer = LLVM::LLVMPointerType::get(ctx);
  Type word = IntegerType::get(ctx, 64);
  return match(
      layout::wordsOf(type),
      [&](layout::Pointer one) { return SmallVector<Component>{{pointer, one.word}}; },
      [&](layout::Integer one) {
        return SmallVector<Component>{{IntegerType::get(ctx, one.bits), one.word}};
      },
      [](layout::Itself one) { return SmallVector<Component>{{one.type, Word::Uncounted}}; },
      [](layout::NoWord) { return SmallVector<Component>{}; },
      [&](layout::Addresses places) {
        return SmallVector<Component>(layout::componentCount(places.of),
                                      Component{pointer, Word::Uncounted});
      },
      [&](layout::Descriptor descriptor) {
        SmallVector<Component> out{{pointer, Word::Cell}};
        out.append(layout::DescriptorFields::of(descriptor.array).carried(),
                   Component{word, Word::Uncounted});
        return out;
      },
      [&](layout::Spread spread) { return sum(spread.data).words; });
}

// The tag, where two constructors or more are possible, then each possible
// constructor's fields, taking the words before them that no field of the
// same constructor took, of the same type and kind, so two constructors
// share their words. A pointer slot some possible constructor leaves empty
// is null there: it may be null.
layout::SumLayout Layouts::sumOf(DataType type) const {
  using layout::Component;
  using layout::Word;
  layout::SumLayout out;
  const families::TagSet &possible = type.unrefined().possibleTags();
  uint32_t declared = type.declaredCount();
  if (possible.size() >= 2) {
    unsigned width = declared <= 256 ? 8u : declared <= 65536 ? 16u : 32u;
    out.tag = IntegerType::get(type.getContext(), width);
    out.words.push_back(Component{*out.tag, Word::Uncounted});
  }
  auto firstField = static_cast<unsigned>(out.words.size());
  out.fields.resize(declared);
  SmallVector<unsigned> users;
  for (Tag tag : possible) {
    // The free words of each component, in word order: built once per
    // constructor, since searching the words again for every field is
    // quadratic in a wide sum.
    llvm::DenseMap<std::pair<Type, unsigned>, SmallVector<unsigned>> free;
    llvm::DenseMap<std::pair<Type, unsigned>, unsigned> cursor;
    for (unsigned i = firstField, n = static_cast<unsigned>(out.words.size()); i < n; ++i)
      free[{out.words[i].type, static_cast<unsigned>(out.words[i].word)}].push_back(i);
    auto &perField = out.fields[static_cast<uint32_t>(tag)];
    for (const SmallVector<Component> &field : fieldsOf(type, tag)) {
      SmallVector<unsigned> taken;
      for (const Component &component : field) {
        std::pair<Type, unsigned> key{component.type, static_cast<unsigned>(component.word)};
        SmallVector<unsigned> &bucket = free[key];
        unsigned &at = cursor[key];
        unsigned chosen;
        if (at < bucket.size()) {
          chosen = bucket[at++];
        } else {
          chosen = static_cast<unsigned>(out.words.size());
          out.words.push_back(component);
          users.push_back(0);
        }
        ++users[chosen - firstField];
        taken.push_back(chosen);
      }
      perField.push_back(std::move(taken));
    }
  }
  for (unsigned i = firstField, n = static_cast<unsigned>(out.words.size()); i < n; ++i)
    if (out.words[i].word == Word::Cell && users[i - firstField] < possible.size())
      out.words[i].word = Word::MaybeCell;
  return out;
}

} // namespace idr
