// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The runtime components of a value type, each with the kind of word it
// is; the plan of a memref's descriptor; and the slots of a data type held
// in place, over the constructors its indices leave possible.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Layout.h"
#include "idr/Support/Match.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/IR/BuiltinTypes.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Twine.h"
#include "llvm/Support/ErrorHandling.h"
#include "llvm/Support/raw_ostream.h"

#include <string>

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

// The integer a fixed-width number's layout is.
Type numberType(MLIRContext *ctx, Layout layout) {
  return IntegerType::get(ctx, families::numberBits(layout));
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
  Type value = unrestricted(type);
  if (auto data = dyn_cast<DataType>(value))
    return data.components();
  if (auto shaped = dyn_cast<ShapedType>(value); shaped && isa<RankedTensorType, MemRefType>(value))
    return 1 + DescriptorFields::of(shaped).carried();
  return 1;
}

Reach reachOf(Type type) {
  Type value = unrestricted(type);
  if (auto data = dyn_cast<DataType>(value))
    return data.boundsReach() ? Reach::Bounded : Reach::Unbounded;
  return holdsReferences(value) ? Reach::Unbounded : Reach::Bounded;
}

} // namespace idr::layout

namespace idr {

// A data type is as its layout says; an array is its cell and what of its
// descriptor its type leaves to the value; a big's word is a small integer
// or a cell's address; a reuse token may be null unless its type says it
// holds its cell; every other value that holds a reference is the address
// of its cell, a value used once by its type (a destination, a cell, a
// package) an address no count is kept of, and a scalar itself.
SmallVector<layout::Component> Layouts::components(Type type) const {
  using layout::Word;
  MLIRContext *ctx = type.getContext();
  Type value = unrestricted(type);
  Type pointer = LLVM::LLVMPointerType::get(ctx);
  Type word = IntegerType::get(ctx, 64);
  if (auto data = dyn_cast<DataType>(value)) {
    switch (data.layout()) {
    case Layout::FrameStack:
      return {{pointer, Word::Uncounted}};
    case Layout::Cell:
      return {{pointer, Word::Cell}};
    case Layout::Natural:
      return {{word, Word::Big}};
    case Layout::InPlace:
      return sum(data).words;
    case Layout::Word8:
    case Layout::Word16:
    case Layout::Word32:
    case Layout::Word64:
      return {{layout::numberType(ctx, data.layout()), Word::Uncounted}};
    }
  }
  if (isa<RankedTensorType, MemRefType>(value)) {
    SmallVector<layout::Component> out{{pointer, Word::Cell}};
    out.append(layout::DescriptorFields::of(cast<ShapedType>(value)).carried(),
               layout::Component{word, Word::Uncounted});
    return out;
  }
  if (isa<BigType, NatType>(value))
    return {{word, Word::Big}};
  if (isa<TokenType>(value))
    return {{pointer, claims(type, Unique::Deep) ? Word::Cell : Word::MaybeCell}};
  if (holdsReferences(value))
    return {{pointer, Word::Cell}};
  if (isLinearByType(value))
    return {{pointer, Word::Uncounted}};
  return {{value, Word::Uncounted}};
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
