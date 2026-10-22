// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Counting's two types: the memory of one cell of a constructor, and the
// reuse token, the set of constructors whose emptied cell it may hold. Each
// is of data types refined to one constructor that has a cell of its own,
// which its parameters say and its verifier holds, so a cell of an atom or
// a token of a value held in place cannot be written. A token's size is
// derived from any of its sources and the target's layout, never stored.

#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Families/Families.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;
using namespace idr;

namespace {

// Whether `type` is a data type refined to one constructor that has a cell
// of its own: what a cell is of, and what a token's cell may have been.
bool cellConstructor(Type type) {
  auto data = dyn_cast<DataType>(type);
  if (!data)
    return false;
  std::optional<Tag> tag = data.singleTag();
  return tag && buildsCell(data, *tag);
}

} // namespace

//===----------------------------------------------------------------------===//
// !idr.cell
//===----------------------------------------------------------------------===//

LogicalResult CellType::verify(function_ref<InFlightDiagnostic()> emitError, Type value) {
  if (!cellConstructor(value))
    return emitError() << "a cell is of a data type refined to one constructor with a cell of "
                          "its own, not of "
                       << value;
  return success();
}

DataType CellType::getData() const { return cast<DataType>(getValue()); }

Tag CellType::getTag() const { return *getData().singleTag(); }

//===----------------------------------------------------------------------===//
// !idr.reuse_token
//===----------------------------------------------------------------------===//

// A set of one or more cell constructors, each named once.
LogicalResult ReuseTokenType::verify(function_ref<InFlightDiagnostic()> emitError,
                                     ArrayRef<Type> sources) {
  if (sources.empty())
    return emitError() << "a token may hold the cell of at least one constructor";
  for (auto [index, source] : llvm::enumerate(sources)) {
    if (!cellConstructor(source))
      return emitError() << "a token's source " << source
                         << " is no data type refined to one constructor with a cell";
    if (llvm::is_contained(sources.take_front(index), source))
      return emitError() << "a token names its source " << source << " twice";
  }
  return success();
}

ReuseTokenType ReuseTokenType::of(DataType source) {
  Type only = source;
  return get(source.getContext(), ArrayRef<Type>(only));
}

// What each token may hold, in the order the tokens name it: the first
// token's sources, then each new one of the next, so the paths a rejoin
// meets in one order give one type.
ReuseTokenType ReuseTokenType::merged(ArrayRef<ReuseTokenType> tokens) {
  SmallVector<Type, 4> sources;
  for (ReuseTokenType token : tokens)
    for (Type source : token.getSources())
      if (!llvm::is_contained(sources, source))
        sources.push_back(source);
  return get(tokens.front().getContext(), sources);
}
