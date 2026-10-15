// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The facts that rule out a crash, which a guard folds away on, and what a
// crash reports.

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "mlir/IR/Matchers.h"

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
  // Appends share subexpressions, so each value is looked at once, and the
  // walk ends with the appends the value is built of.
  OnceWorklist<Value> work;
  work.push(value);
  while (std::optional<Value> next = work.pop()) {
    Attribute constant;
    if (matchPattern(*next, m_Constant(&constant))) {
      if (CheckNonemptyOp::holds(constant))
        return true;
      continue;
    }
    Operation *def = next->getDefiningOp();
    if (isa_and_nonnull<StrConsOp, StrFromCharOp, StrShowOp, BigShowOp>(def))
      return true;
    if (auto append = dyn_cast_or_null<StrAppendOp>(def)) {
      work.push(append.getLhs());
      work.push(append.getRhs());
    }
  }
  return false;
}

std::optional<StringRef> CrashOp::getCrashCause() { return getMessage(); }
