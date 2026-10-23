// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The predicates this area's operand and result constraints name
// (Spec.Ops.Shapes), which data cannot say: a runtime value at a grade, by
// its carrier and its uses (Grades.h); base's list, by its family's shape;
// a buffer of bytes. The generated constraints call them.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Families/Declaration.h"
#include "idr/IR/Grades.h"

#include "mlir/IR/BuiltinTypes.h"

using namespace mlir;

namespace idr {

namespace {

// A value of carrier `T` at any grade: what an op makes.
template <typename T>
bool carried(Type type) {
  return isa<T>(unrestricted(type));
}

// A value used any number of times: what an op reads in place. A value used
// once reaches a primitive only through a cast to many.
bool readInPlace(Type type) { return usesOf(type) == Uses::Many; }

// A list read in place whose element is `element`: a family of base's
// list's shape, a constructor with no field and one of an element and the
// list, read off its declaration.
template <typename Element>
bool listOf(Type type, Element element) {
  if (!readInPlace(type))
    return false;
  auto data = dyn_cast<DataType>(unrestricted(type));
  if (!data)
    return false;
  std::optional<families::ListShape> shape = data.listShape();
  if (!shape)
    return false;
  return element(unrestricted(data.ctor(shape->cons).fields[shape->element]));
}

} // namespace

bool isStrRead(Type type) { return carried<StrType>(type) && readInPlace(type); }
bool isStrValue(Type type) { return carried<StrType>(type); }
bool isStrStatic(Type type) { return isStrRead(type) && freedBy(type, Release::Static); }
bool isBigRead(Type type) { return carried<BigType>(type) && readInPlace(type); }
bool isBigValue(Type type) { return carried<BigType>(type); }
bool isNatRead(Type type) { return carried<NatType>(type) && readInPlace(type); }
bool isNatValue(Type type) { return carried<NatType>(type); }
// An Integer or a natural, the values the big ops take, as the type answers
// (NumericTypeInterface).
bool isBigOrNatRead(Type type) { return isCarriedAsBig(type) && readInPlace(type); }
bool isBigOrNatValue(Type type) { return isCarriedAsBig(type); }
// A small: a word with no cell, so nothing frees it and no count writes it.
bool isBigOrNatStatic(Type type) { return isBigOrNatRead(type) && freedBy(type, Release::Static); }

bool isListOfChars(Type type) {
  return listOf(type, [](Type element) { return element.isInteger(32); });
}

bool isListOfStrings(Type type) {
  return listOf(type, [](Type element) { return isa<StrType>(element); });
}

// An array of mutable memory of one dimension whose elements are bytes, as
// every buffer op reads and writes them.
bool isByteBuffer(Type type) {
  if (!isRank1Array(unrestricted(type)))
    return false;
  return cast<MemRefType>(unrestricted(type)).getElementType().isInteger(8);
}

} // namespace idr
