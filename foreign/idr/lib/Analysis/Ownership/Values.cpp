// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which values hold references, as one run counts them, and which ones
// exclusivity follows.
#include "idr/Analysis/Ownership.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"

#include "mlir/IR/SymbolTable.h"

using namespace mlir;

namespace idr::ownership {

// Owned boxes and unboxed sums, whose slots may hold boxes, and the tokens
// of their cells: what a take hands out or a reuse builds in.
bool followed(Value value) {
  Type type = value.getType();
  return isOwned(type) && isa<BoxType, DataType, TokenType>(unrestricted(type));
}

bool Counted::operator()(Type type) {
  auto [known, fresh] = answers.try_emplace(type, false);
  if (fresh)
    known->second = holdsReferences(type, [&](Type sum) { return lookupData(symbols, sum); });
  return known->second;
}

bool Counted::tracked(Value value) { return (*this)(value.getType()) && !isStatic(value); }

} // namespace idr::ownership
