// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value of each type of the module can hold a reference to: the
// containment among its declarations and arrays, and its cycles. The
// module verifier builds one directly to refuse a type that contains itself
// and an array that can reach itself; a pass takes it from the analysis
// manager, and it never changes once built, so function passes may read it
// from any thread.
#ifndef IDR_IR_TYPEGRAPH_H
#define IDR_IR_TYPEGRAPH_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr {

// A node is a declaration, by its value type, or an array; an edge goes
// from a declaration to what its constructors' fields name and from an
// array to what its element names, through grades. Every declaration is
// numbered first, in module order, so a declaration's node is its position
// among the module's idr.data ops; the types its fields name follow.
class TypeGraph {
public:
  explicit TypeGraph(mlir::Operation *module);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<TypeGraph>();
  }

  unsigned size() const { return static_cast<unsigned>(types.size()); }
  // The node of a declaration's value type or of an array type, through its
  // grade; none for a type no field, element or declaration names.
  std::optional<unsigned> node(mlir::Type type) const;
  mlir::Type type(unsigned at) const { return types[at]; }
  bool isArray(unsigned at) const;
  // The declaration of a node, null for an array or an undeclared type.
  idr::DataOp declaration(unsigned at) const { return declarations[at]; }
  llvm::ArrayRef<unsigned> successors(unsigned at) const { return edges[at]; }
  // The strongly connected components, callees first.
  llvm::ArrayRef<llvm::SmallVector<unsigned>> components() const { return parts; }

  // The sets of types that reach one another through an array: each
  // component of two or more with an array in it.
  llvm::SmallVector<llvm::SmallVector<unsigned>> knots() const;
  // The cycle of `component` through its array `array`, by a shortest path:
  // from what the array holds back to the array, and to what it holds again.
  llvm::SmallVector<unsigned> cycle(unsigned array, llvm::ArrayRef<unsigned> component) const;
  // Every unboxed declaration that holds itself inline, through unboxed
  // declarations only, in module order.
  llvm::SmallVector<idr::DataOp> containsItself() const;

private:
  unsigned insert(mlir::Type type);
  void edge(unsigned from, mlir::Type type);

  llvm::SmallVector<mlir::Type> types;
  llvm::SmallVector<idr::DataOp> declarations;
  llvm::SmallVector<llvm::SmallVector<unsigned>> edges;
  llvm::DenseMap<mlir::Type, unsigned> index;
  llvm::SmallVector<llvm::SmallVector<unsigned>> parts;
};

} // namespace idr

#endif // IDR_IR_TYPEGRAPH_H
