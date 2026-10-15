// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What each function's body names: every function a symbol use in it
// resolves to, the edges every cycle of references follows, and how large
// the body is. The passes that follow references ask the same questions of
// every function: one walk of each body answers them.
//
// The analysis is built whole in its constructor, each body walked on a
// worker into its own slot and the slots merged in module order, and never
// changes afterwards: a function pass reads it through its parent from any
// thread, so nothing is filled on first ask.
#ifndef IDR_ANALYSIS_REFERENCES_H
#define IDR_ANALYSIS_REFERENCES_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>

namespace idr {

class References {
public:
  // One reference: `target` is named by `at`, the op one of whose stored
  // attributes holds a symbol reference to it: a call's callee, a closure's
  // or suspension's label, a label constructor (named by its function), a
  // match's case of one, a constant that holds one.
  struct Site {
    idr::FuncOp target;
    mlir::Operation *at;
  };

  References(mlir::Operation *module, mlir::AnalysisManager &am);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<References>() || !pa.isPreserved<mlir::SymbolTable>();
  }

  // Every idr.func of the module, in module order.
  llvm::ArrayRef<idr::FuncOp> functions() const { return fns; }
  // The references of `fn`, in walk order. None for a function it did not
  // see.
  llvm::ArrayRef<Site> of(idr::FuncOp fn) const;
  // Whether the body of `fn` holds a call, an idr.apply included.
  bool hasCall(idr::FuncOp fn) const;
  // How many operations the body of `fn` holds: what a walk of it counts.
  int64_t ops(idr::FuncOp fn) const;
  // The strongly connected components of the graph of the references,
  // callees first.
  llvm::ArrayRef<llvm::SmallVector<idr::FuncOp>> components() const { return parts; }
  // Whether `fn` is on a component of two or more, or names itself.
  bool isRecursive(idr::FuncOp fn) const;

private:
  std::optional<unsigned> position(idr::FuncOp fn) const;

  llvm::SmallVector<idr::FuncOp> fns;
  llvm::DenseMap<mlir::Operation *, unsigned> positions;
  // Every function's sites, one after another; `offsets[at]` is where those
  // of the function at `at` begin, and `offsets[at + 1]` where they end.
  llvm::SmallVector<Site> sites;
  llvm::SmallVector<unsigned> offsets;
  llvm::BitVector calls;
  llvm::BitVector recursive;
  llvm::SmallVector<int64_t> sizes;
  llvm::SmallVector<llvm::SmallVector<idr::FuncOp>> parts;
};

// Calls `visit` on every attribute nested in what `op` stores, inherent and
// discardable. The op's whole dictionary would be built from its
// properties, a new attribute in the context, and the workers that ask
// make none.
void walkStoredAttributes(mlir::Operation *op, llvm::function_ref<void(mlir::Attribute)> visit);

} // namespace idr

#endif // IDR_ANALYSIS_REFERENCES_H
