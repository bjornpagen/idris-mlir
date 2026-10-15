// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value of each type of the module can hold a reference to: the
// containment among its data types and arrays, and its cycles, read from
// the types the module's values are of and the bodies those hold. The
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

// A node is a data type or an array; an edge goes from a data type to what
// its constructors' fields name, held in place or in a box, and from an
// array to what its element names, through grades. Every data type is
// numbered first, in the order of their names, so the numbering is the
// module's content alone; the arrays follow, as their holders meet them.
class TypeGraph {
public:
  explicit TypeGraph(mlir::Operation *module);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<TypeGraph>();
  }

  unsigned size() const { return static_cast<unsigned>(types.size()); }
  // The node of a data type (in place or in a box) or of an array type,
  // through its grade; none for a type no value, field or element is of.
  std::optional<unsigned> node(mlir::Type type) const;
  mlir::Type type(unsigned at) const { return types[at]; }
  bool isArray(unsigned at) const;
  // The data type of a node, null for an array.
  DataType declaration(unsigned at) const { return llvm::dyn_cast<DataType>(types[at]); }
  // Whether some value or field holds the node's data type in a box, and
  // whether some holds it in place.
  bool boxed(unsigned at) const { return heldBoxed[at]; }
  bool inlined(unsigned at) const { return heldInPlace[at]; }
  llvm::ArrayRef<unsigned> successors(unsigned at) const { return edges[at]; }
  // The strongly connected components, callees first.
  llvm::ArrayRef<llvm::SmallVector<unsigned>> components() const { return parts; }

  // The sets of types that reach one another through an array: each
  // component of two or more with an array in it.
  llvm::SmallVector<llvm::SmallVector<unsigned>> knots() const;
  // The cycle of `component` through its array `array`, by a shortest path:
  // from what the array holds back to the array, and to what it holds again.
  llvm::SmallVector<unsigned> cycle(unsigned array, llvm::ArrayRef<unsigned> component) const;
  // Every data type that holds itself in place, through data types held in
  // place only, in name order.
  llvm::SmallVector<DataType> containsItself() const;

private:
  unsigned insert(mlir::Type type);
  // Notes how a value or a field of `type` holds what it names.
  void held(mlir::Type type);
  void edge(unsigned from, mlir::Type type);

  llvm::SmallVector<mlir::Type> types;
  llvm::SmallVector<bool> heldBoxed, heldInPlace;
  llvm::SmallVector<llvm::SmallVector<unsigned>> edges;
  // For each node, its successors held in place.
  llvm::SmallVector<llvm::SmallVector<unsigned>> inPlace;
  llvm::DenseMap<mlir::Type, unsigned> index;
  llvm::SmallVector<llvm::SmallVector<unsigned>> parts;
};

} // namespace idr

#endif // IDR_IR_TYPEGRAPH_H
