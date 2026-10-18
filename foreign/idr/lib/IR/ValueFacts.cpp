// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value of each type holds, ValueFactsTypeInterface's answers: every
// type of the dialect gives its own, a data type from its body, computed
// once and kept beside it; the builtin types a value may have answer as
// external models, attached when the dialect registers its types, with the
// builtin integers' literals.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/TypeGraph.h"
#include "idr/Support/Scc.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"

#include <functional>

using namespace mlir;
using namespace idr;

namespace {

// What a builtin scalar or vector holds: nothing a count or a world is,
// and it is used as often as its grade says. A vector's elements are
// scalars.
template <typename T>
struct ScalarFacts : ValueFactsTypeInterface::ExternalModel<ScalarFacts<T>, T> {
  bool holdsReferences(Type) const { return false; }
  bool holdsWorld(Type) const { return false; }
  bool isLinearByType(Type) const { return false; }
  bool isCounted(Type) const { return false; }
  bool isCellPointer(Type) const { return false; }
};

// An array's cell is a reference, and its elements hold what their type
// holds. A buffer is counted; a value array is counted as its buffer, after
// bufferization. Its value is a descriptor, the cell with what of its shape
// the type leaves open, not one pointer.
template <typename T, bool counted>
struct ArrayFacts : ValueFactsTypeInterface::ExternalModel<ArrayFacts<T, counted>, T> {
  bool holdsReferences(Type) const { return true; }
  bool holdsWorld(Type type) const { return idr::holdsWorld(cast<T>(type).getElementType()); }
  bool isLinearByType(Type) const { return false; }
  bool isCounted(Type) const { return counted; }
  bool isCellPointer(Type) const { return false; }
};

// A literal of an integer type is an integer of that type, written as a
// number that fits its width; i1's are written true and false too.
struct IntegerLiterals : LiteralTypeInterface::ExternalModel<IntegerLiterals, IntegerType> {
  bool isLiteral(Type type, Attribute literal) const {
    auto integer = dyn_cast<IntegerAttr>(literal);
    return integer && integer.getType() == type;
  }

  ParseResult parseLiteral(Type type, AsmParser &parser, Attribute &literal) const {
    auto integer = cast<IntegerType>(type);
    unsigned width = integer.getWidth();
    if (width == 1) {
      if (succeeded(parser.parseOptionalKeyword("true"))) {
        literal = IntegerAttr::get(integer, 1);
        return success();
      }
      if (succeeded(parser.parseOptionalKeyword("false"))) {
        literal = IntegerAttr::get(integer, 0);
        return success();
      }
    }
    APInt value;
    SMLoc loc = parser.getCurrentLocation();
    if (parser.parseInteger(value))
      return failure();
    if ((value.isNegative() ? value.getSignificantBits() : value.getActiveBits()) > width)
      return parser.emitError(loc, "key does not fit in ") << type;
    literal = IntegerAttr::get(
        integer, value.isNegative() ? value.sextOrTrunc(width) : value.zextOrTrunc(width));
    return success();
  }
};

} // namespace

void IdrDialect::registerValueFacts() {
  MLIRContext &context = *getContext();
  IntegerType::attachInterface<ScalarFacts<IntegerType>>(context);
  IntegerType::attachInterface<IntegerLiterals>(context);
  IndexType::attachInterface<ScalarFacts<IndexType>>(context);
  BFloat16Type::attachInterface<ScalarFacts<BFloat16Type>>(context);
  Float16Type::attachInterface<ScalarFacts<Float16Type>>(context);
  Float32Type::attachInterface<ScalarFacts<Float32Type>>(context);
  Float64Type::attachInterface<ScalarFacts<Float64Type>>(context);
  Float80Type::attachInterface<ScalarFacts<Float80Type>>(context);
  Float128Type::attachInterface<ScalarFacts<Float128Type>>(context);
  VectorType::attachInterface<ScalarFacts<VectorType>>(context);
  MemRefType::attachInterface<ArrayFacts<MemRefType, true>>(context);
  UnrankedMemRefType::attachInterface<ArrayFacts<UnrankedMemRefType, true>>(context);
  RankedTensorType::attachInterface<ArrayFacts<RankedTensorType, false>>(context);
  UnrankedTensorType::attachInterface<ArrayFacts<UnrankedTensorType, false>>(context);
}

bool idr::holdsReferences(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts && facts.holdsReferences();
}

bool idr::holdsWorld(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts && facts.holdsWorld();
}

bool idr::isLinearByType(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts && facts.isLinearByType();
}

bool idr::isCounted(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts && facts.isCounted();
}

bool idr::isCellPointer(Type type) {
  auto facts = dyn_cast<ValueFactsTypeInterface>(type);
  return facts && facts.isCellPointer();
}

// A grade is a fact of how the value is used, not of what it holds, so it
// answers as its value; that value is never one used once by its type,
// whose grade QType::verify refuses.
bool QType::holdsReferences() const { return idr::holdsReferences(getValue()); }
bool QType::holdsWorld() const { return idr::holdsWorld(getValue()); }
bool QType::isLinearByType() const { return idr::isLinearByType(getValue()); }
bool QType::isCounted() const { return idr::isCounted(getValue()); }
bool QType::isCellPointer() const { return idr::isCellPointer(getValue()); }

// A box is a reference to a cell, which holds what its data type holds.
bool BoxType::holdsReferences() const { return true; }
bool BoxType::holdsWorld() const { return getData().holdsWorld(); }
bool BoxType::isLinearByType() const { return false; }
bool BoxType::isCounted() const { return true; }
bool BoxType::isCellPointer() const { return true; }

// A closure's cell, whose captures are no types until idr-defunctionalize
// makes its sum, and none is a world. Its quantity is its grade's: a
// closure that captures a linear value is graded at quantity one.
bool FnType::holdsReferences() const { return true; }
bool FnType::holdsWorld() const { return false; }
bool FnType::isLinearByType() const { return false; }
bool FnType::isCounted() const { return true; }
bool FnType::isCellPointer() const { return true; }

// A suspension's cell, whose captures are no types until
// idr-defunctionalize makes its memo sum.
bool LazyType::holdsReferences() const { return true; }
bool LazyType::holdsWorld() const { return false; }
bool LazyType::isLinearByType() const { return false; }
bool LazyType::isCounted() const { return true; }
bool LazyType::isCellPointer() const { return true; }

bool StrType::holdsReferences() const { return true; }
bool StrType::holdsWorld() const { return false; }
bool StrType::isLinearByType() const { return false; }
bool StrType::isCounted() const { return true; }
bool StrType::isCellPointer() const { return true; }

// A big's word is a small integer or a cell's address.
bool BigType::holdsReferences() const { return true; }
bool BigType::holdsWorld() const { return false; }
bool BigType::isLinearByType() const { return false; }
bool BigType::isCounted() const { return true; }
bool BigType::isCellPointer() const { return false; }

bool NatType::holdsReferences() const { return true; }
bool NatType::holdsWorld() const { return false; }
bool NatType::isLinearByType() const { return false; }
bool NatType::isCounted() const { return true; }
bool NatType::isCellPointer() const { return false; }

// The world has no runtime form at all, and each is used exactly once.
bool WorldType::holdsReferences() const { return false; }
bool WorldType::holdsWorld() const { return true; }
bool WorldType::isLinearByType() const { return true; }
bool WorldType::isCounted() const { return false; }
bool WorldType::isCellPointer() const { return false; }

// A destination is the address of a word a later write fills, exactly
// once: it holds nothing until then, and the word is inside a cell, not
// its start.
bool DestType::holdsReferences() const { return false; }
bool DestType::holdsWorld() const { return false; }
bool DestType::isLinearByType() const { return true; }
bool DestType::isCounted() const { return false; }
bool DestType::isCellPointer() const { return false; }

// A cell's memory, owned until it is built again, or null where the cell
// was shared.
bool idr::TokenType::holdsReferences() const { return true; }
bool idr::TokenType::holdsWorld() const { return false; }
bool idr::TokenType::isLinearByType() const { return false; }
bool idr::TokenType::isCounted() const { return true; }
bool idr::TokenType::isCellPointer() const { return false; }

// A data type's values hold what its constructors' fields hold. A
// reference is held in place, through the data types held in place; a
// world anywhere a value reaches, in place, in a box or in an array's
// elements. Each is a least fixpoint over the containment among data
// types, which one pass over its components, callees first, reaches: a
// cycle holds what its members hold.
// The first question computes the answer for every data type it depends on
// that has none yet, and keeps it, unless a type it met is still being made
// (only the parser and define see one), whose body is still to come. A body
// may name types whose bodies come after it, so no setting of one body sees
// the answer whole. Two threads that ask at once may each compute it, and
// keep the same.
Held DataType::facts() const {
  if (std::optional<Held> known = knownFacts())
    return *known;
  // The data types without an answer, from this one, each numbered once as
  // it is met, so the table ends with the types this one reaches; each with
  // what its fields are themselves and the data types they name.
  SmallVector<DataType> nodes{*this};
  llvm::DenseMap<DataType, unsigned> indexOf{{*this, 0u}};
  SmallVector<Held> local;
  SmallVector<SmallVector<unsigned>> named, inPlace;
  bool complete = true;
  for (size_t at = 0; at < nodes.size(); ++at) {
    DataType node = nodes[at];
    complete &= node.bodySet();
    Held own = Held::Nothing;
    Held reached = Held::Nothing;
    SmallVector<unsigned> successors, inPlaceSuccessors;
    auto onData = [&](DataType data, bool heldInPlace) {
      if (std::optional<Held> answer = data.knownFacts()) {
        reached |= *answer & Held::World;
        if (heldInPlace)
          own |= *answer & Held::References;
        return;
      }
      auto [it, fresh] = indexOf.try_emplace(data, static_cast<unsigned>(nodes.size()));
      if (fresh)
        nodes.push_back(data);
      unsigned index = it->second;
      successors.push_back(index);
      if (heldInPlace)
        inPlaceSuccessors.push_back(index);
    };
    // What a field names, through the arrays a world orders, whose
    // elements a value holds through their cell: each array's element is a
    // part of the array's type, so the recursion ends.
    std::function<void(Type)> reach = [&](Type field) {
      forEachNamed(
          field, onData, [&](MemRefType array) { reach(array.getElementType()); },
          [&](Type leaf) {
            if (idr::holdsWorld(leaf))
              reached |= Held::World;
          });
    };
    for (const Ctor &ctor : node.getCtors())
      for (Type field : ctor.fields) {
        reach(field);
        // A reference held by anything but a data type in place is the
        // field's own: a box, a string, an array's cell.
        Type value = unrestricted(field);
        if (!isa<DataType>(value) && idr::holdsReferences(value))
          own |= Held::References;
      }
    local.push_back(own | reached);
    named.push_back(std::move(successors));
    inPlace.push_back(std::move(inPlaceSuccessors));
  }
  // A world along every edge; a reference along the edges in place.
  SmallVector<Held> held(local);
  auto solve = [&](ArrayRef<SmallVector<unsigned>> edges, Held mask) {
    for (const SmallVector<unsigned> &component : idr::components(edges)) {
      Held inComponent = Held::Nothing;
      for (unsigned vertex : component) {
        inComponent |= local[vertex] & mask;
        for (unsigned next : edges[vertex])
          inComponent |= held[next] & mask;
      }
      for (unsigned vertex : component)
        held[vertex] = (held[vertex] & ~mask) | inComponent;
    }
  };
  solve(named, Held::World);
  solve(inPlace, Held::References);
  if (complete)
    for (auto [node, answer] : llvm::zip_equal(nodes, held))
      node.keepFacts(answer);
  return held.front();
}

bool DataType::holdsReferences() const { return any(facts() & Held::References); }
bool DataType::holdsWorld() const { return any(facts() & Held::World); }
// A constructor value is used as often as its grade says.
bool DataType::isLinearByType() const { return false; }
bool DataType::isCounted() const { return holdsReferences(); }
// A sum held in place is its slots: the slots of the constructors it is not
// are empty.
bool DataType::isCellPointer() const { return false; }
