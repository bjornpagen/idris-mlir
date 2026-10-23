// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the lifetimes' rule of one function keeps as its walk goes, shared
// by the rule's three units (lib/IR/Lifetimes/Verify.cpp, Proof.cpp and
// Loans.cpp): the lifetimes open where it stands (OpenLifetimes, which each
// op's own rule reads too), the regions it is in, each with how many
// regions that run again enclose it, and whether the program's references
// are counted. No rule follows a def-use chain but the rule of loans, whose
// bare aliases name no lifetime; and whether a use runs again inside a
// lifetime is two counts compared, so none walks up.
#ifndef IDR_IR_LIFETIMES_RULES_H
#define IDR_IR_LIFETIMES_RULES_H

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes/Open.h"
#include "idr/IR/Verify.h"

// Whether the program's references are counted (StageCounting), which the
// rule of loans reads off the program's stage.
#include "idr/IR/Generated/StageFacts.h.inc"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Region.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/SmallVector.h"

#include <cstddef>

namespace idr::verify {

struct LifetimeRules::State {
  // A region the walk is in: how many lifetimes were open when it was
  // entered, and how many regions that run again enclose it, it included.
  struct Level {
    std::size_t openAt;
    unsigned again;
  };

  explicit State(FuncOp fn)
      : fn(fn), open(fn), counting(countingAt[fn.getProgram().getStage()]) {}

  mlir::LogicalResult enter(mlir::Operation *op, mlir::Region &region);
  void leave();
  mlir::LogicalResult check(mlir::Operation &op);

  // Whether `op` states `lifetime` for some value it makes (Verify.cpp).
  static bool states(mlir::Operation &op, mlir::Value lifetime);

  // The local rules of one op (Verify.cpp), the frame-limited rule at
  // each use it makes of a lifetime (Proof.cpp), and the rule of a loan,
  // at the idr.carrier that makes it (Loans.cpp).
  mlir::LogicalResult local(mlir::Operation &op);
  mlir::LogicalResult proof(mlir::Operation &user);
  mlir::LogicalResult loans(mlir::Operation &op);
  static bool keptHere(mlir::Operation &user, mlir::Value lifetime);

  FuncOp fn;
  OpenLifetimes open;
  StageCounting counting;
  llvm::SmallVector<Level, 16> levels;
};

} // namespace idr::verify

#endif // IDR_IR_LIFETIMES_RULES_H
