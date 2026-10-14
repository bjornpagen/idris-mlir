// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a call of each function may do besides computing its results:
// perform IO, crash, or fail to return, as the dialect's Effect bits. The
// analysis is built whole in its constructor, each body walked on a worker
// into its own slot and the bits propagated once, serially, over the
// components of the references; it never changes afterwards.
#ifndef IDR_ANALYSIS_EFFECTS_H
#define IDR_ANALYSIS_EFFECTS_H

#include "idr/IR/IdrDialect.h"
#include "idr/Analysis/Holds.h"
#include "idr/Analysis/References.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

namespace idr {

// Everything a call may do: what an absent `effects` means, and what no
// writer stores.
constexpr idr::Effect anyEffect = idr::Effect::io | idr::Effect::crash | idr::Effect::diverge;

class Effects {
public:
  // A call of a function may perform IO when it takes a world, as a
  // parameter or in data one holds. That is a fact of its type: a world
  // reaches a function only through its parameters, since no op makes one
  // from nothing but idr.world.new, which counts where it is. So a function
  // that only builds IO actions, as a fold that makes `a *> b` does,
  // performs no IO; whoever runs an action gives it a world.
  //
  // A function may crash when it reaches an op that may crash, through the
  // functions it calls and the labels of the closures it makes. A closure's
  // crash counts where it is made, and also where it is passed: a call
  // given one is judged by what the closure may do too (`passed`).
  //
  // A function may diverge when its own body may: it lacks `total`, Idris's
  // proof that every loop of it terminates. And it may when it reaches one
  // that may, the same way as a crash. That holds through a function Idris
  // proved too: its proof counts the calls Idris saw, and a call of an
  // interface's method, which reaches the implementation only once the
  // dictionary is known, is not one of them.
  //
  // A function without a body, and every function that reaches one or
  // calls anything but an idr.call or an idr.apply, may do all three.
  Effects(mlir::Operation *module, mlir::AnalysisManager &am);

  // Unless it and every analysis it was computed from are preserved.
  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const;

  // What a call of `fn` may do, from the module as it is; anyEffect for a
  // function it did not see.
  idr::Effect of(idr::FuncOp fn) const;
  // What code given `value` may do by applying the closures it holds.
  idr::Effect passed(mlir::Value value) const;
  // What the fact on `fn` says: anyEffect when `fn` is null, external or
  // unmarked. A pass that runs after idr-effects in a round reads a
  // callee's this way, and sees it as idr-effects left it.
  static idr::Effect declared(idr::FuncOp fn);

private:
  idr::Effect label(mlir::StringAttr name) const;
  idr::Effect inConstant(mlir::Attribute constant) const;

  const Holds &holds;
  mlir::SymbolTable &symbols;
  llvm::DenseMap<mlir::Operation *, unsigned> positions;
  llvm::SmallVector<idr::Effect> answers;
};

} // namespace idr

#endif // IDR_ANALYSIS_EFFECTS_H
