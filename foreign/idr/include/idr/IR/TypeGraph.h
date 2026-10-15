// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value of each type of the module can hold a reference to: the
// containment among its data types and arrays, and its cycles, read from
// the types the module's values are of and the bodies those hold. The
// verifier builds one directly to refuse a type that contains itself and an
// array that can reach itself, and layout::fit to decide the boxes; a pass
// takes it from the analysis manager, and it never changes once built, so
// function passes may read it from any thread.
#ifndef IDR_IR_TYPEGRAPH_H
#define IDR_IR_TYPEGRAPH_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLFunctionalExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr {

// One step down the containment among types, said once for the type graph
// and for the facts a data type keeps of what its values hold: what a value
// or a field of `type` names, seen through its grade. A data type held in
// place or in a box goes to `data`, with whether it is held in place; an
// array a world orders, to `array`, which names what its element names
// through its cell; a value array (a tensor, or its buffer) is looked
// through, its element held out of place; anything else, which names no
// type, goes to `leaf`.
void forEachNamed(mlir::Type type, llvm::function_ref<void(DataType data, bool inPlace)> data,
                  llvm::function_ref<void(mlir::MemRefType array)> array,
                  llvm::function_ref<void(mlir::Type leaf)> leaf);

// A node is a data type or an array a world orders; an edge goes from a
// data type to what its constructors' fields name (forEachNamed), held in
// place, in a box or in a value array's elements, and from an array to what
// its element names. Every data type is numbered first, in the order of
// their names, so the numbering is the module's content alone; the arrays
// follow, as their holders meet them.
class TypeGraph {
public:
  explicit TypeGraph(mlir::Operation *module);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<TypeGraph>();
  }

  // The type of a node: a data type, or an array a world orders.
  mlir::Type type(unsigned at) const { return types[at]; }
  bool isArray(unsigned at) const { return at >= dataTypes.size(); }
  // The data types, which are the first nodes, in the order of their names.
  llvm::ArrayRef<DataType> declarations() const { return dataTypes; }
  // Whether some value or field holds `data` in a box, and whether some
  // holds it in place.
  bool boxed(DataType data) const { return heldBoxed.contains(data); }
  bool inlined(DataType data) const { return heldInPlace.contains(data); }

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
  // The edges from `from` to what a field or an element of `type` names.
  void edges(unsigned from, mlir::Type type);

  llvm::SmallVector<DataType> dataTypes;
  // Every node's type: the data types, then the arrays.
  llvm::SmallVector<mlir::Type> types;
  llvm::DenseSet<DataType> heldBoxed, heldInPlace;
  llvm::SmallVector<llvm::SmallVector<unsigned>> successorsOf;
  // For each node, its successors held in place.
  llvm::SmallVector<llvm::SmallVector<unsigned>> inPlace;
  llvm::DenseMap<mlir::Type, unsigned> index;
  // The strongly connected components, callees first.
  llvm::SmallVector<llvm::SmallVector<unsigned>> parts;
};

} // namespace idr

#endif // IDR_IR_TYPEGRAPH_H
