// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The facts that rule out a crash, which a guard folds away on, and what a
// crash reports.

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Matchers.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;
using namespace idr;

// A constant other than zero, an integer or a big: a guard of a divisor
// folds away on it.
bool idr::knownNonZero(Value value) {
  Attribute constant;
  return matchPattern(value, m_Constant(&constant)) && CheckNonzeroOp::holds(constant);
}

// A finite Double constant: a guard of a cast folds away on it.
bool idr::knownFinite(Value value) {
  Attribute constant;
  return matchPattern(value, m_Constant(&constant)) && CheckFiniteOp::holds(constant);
}

// A string that cannot be empty: a non-empty constant, or a string built
// with a character or a number in it. A guard of its head or its tail folds
// away on it, and a match on it never takes the case "".
bool idr::knownNonEmpty(Value value) {
  // Appends share subexpressions. Walking both sides of each without
  // remembering a value walks the shared part again on every path.
  SmallVector<Value> work{value};
  llvm::SmallPtrSet<Value, 8> seen;
  while (!work.empty()) {
    Value next = work.pop_back_val();
    if (!seen.insert(next).second)
      continue;
    Attribute constant;
    if (matchPattern(next, m_Constant(&constant))) {
      if (CheckNonemptyOp::holds(constant))
        return true;
      continue;
    }
    Operation *def = next.getDefiningOp();
    if (isa_and_nonnull<StrConsOp, StrFromCharOp, StrShowOp, BigShowOp>(def))
      return true;
    if (auto append = dyn_cast_or_null<StrAppendOp>(def)) {
      work.push_back(append.getLhs());
      work.push_back(append.getRhs());
    }
  }
  return false;
}

std::optional<StringRef> CrashOp::getCrashCause() { return getMessage(); }
