// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What each function's body names: the functions it may run while it runs,
// the edges every cycle of references follows, and how large the body is.
// The passes that follow calls and closures ask the same questions of every
// function, and an interpretation of a cycle asks them again for every
// assignment of abstract values: one walk of each body answers them.
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
  // One reference: `target` is named by `at`, the idr.call, idr.closure,
  // idr.suspend or idr.con that names it, or the op whose attribute holds
  // the constant that does.
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
  // The references of `fn`, in walk order; an idr.call's own is the first
  // of its op's. None for a function without a body or one it did not see.
  llvm::ArrayRef<Site> of(idr::FuncOp fn) const;
  // Whether the body of `fn` holds a call, an idr.apply included.
  bool hasCall(idr::FuncOp fn) const;
  // Whether the body of `fn` calls something that is neither an idr.call
  // nor an idr.apply, or names a function the module lacks.
  bool callsUnknown(idr::FuncOp fn) const;
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
  llvm::BitVector unknown;
  llvm::BitVector recursive;
  llvm::SmallVector<int64_t> sizes;
  llvm::SmallVector<llvm::SmallVector<idr::FuncOp>> parts;
};

// The function a constructor of a sum of closures or of a memo sum names:
// such a sum (an idr.data with `closures`, or with `memo`) has one
// constructor per label, named after the label's function, which a memo
// sum's `labels` names besides its two states. Null for any other
// constructor. The one rule of a label, for References' sites,
// Effects::passed and the facts idr-lower hands LLVM.
mlir::StringAttr closureLabel(mlir::SymbolTable &symbols, mlir::SymbolRefAttr ctor);

// Calls `visit` on every attribute nested in what `op` stores, inherent and
// discardable. The op's whole dictionary would be built from its
// properties, a new attribute in the context, and the workers that ask
// make none.
void walkStoredAttributes(mlir::Operation *op, llvm::function_ref<void(mlir::Attribute)> visit);

} // namespace idr

#endif // IDR_ANALYSIS_REFERENCES_H
