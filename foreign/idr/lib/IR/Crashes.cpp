// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The fact beyond a constant that rules out the crash of a string's head or
// tail, which a guard folds away on, and what a crash reports.

#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

// A string that cannot be empty: a non-empty constant, a string its builder
// says is never empty (one built with a character or a number in it), or an
// append of such a string and another. A guard of its head or its tail folds
// away on it, and a match on it never takes the case "".
bool idr::knownNonEmpty(Value value) {
  // Appends share subexpressions, so each value is looked at once, and the
  // walk ends with the appends the value is built of.
  OnceWorklist<Value> work;
  work.push(value);
  while (std::optional<Value> next = work.pop()) {
    Attribute constant;
    if (matchPattern(*next, m_Constant(&constant))) {
      if (CheckNonemptyOp::holds(CheckNonemptyOp::FoldAdaptor(ArrayRef<Attribute>(constant))))
        return true;
      continue;
    }
    Operation *def = next->getDefiningOp();
    // An append is not empty when either of its parts is not, which only
    // its parts tell: essential, the one builder whose answer is its
    // operands'.
    if (auto append = dyn_cast_or_null<StrAppendOp>(def)) {
      work.push(append.getLhs());
      work.push(append.getRhs());
      continue;
    }
    if (auto builder = dyn_cast_or_null<StrBuilderOpInterface>(def); builder && builder.nonEmpty())
      return true;
  }
  return false;
}

StringRef CrashOp::getCrashCause() { return getMessage(); }
