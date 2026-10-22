// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a value of each type of the module can hold a reference to: the
// containment among the members of its families and its arrays, and the
// cycles through an array, read from the types the module's values are of
// and the declarations those name. The knots verifier reads it to refuse an
// array that can reach itself; a pass takes it from the analysis manager,
// and it never changes once built, so function passes may read it from any
// thread.
//
// Nothing here asks whether a data type holds itself in place: where it is
// held is its layout, which the class rule computes, and a member of a
// group that holds itself is a cell at every index the rule cannot unfold.
#ifndef IDR_IR_TYPEGRAPH_H
#define IDR_IR_TYPEGRAPH_H

#include "idr/Analysis/Solver/Components.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"

#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <utility>

namespace idr {

class TypeGraph;

// A node of the type graph: a member of a family, or an array a world
// orders.
struct TypeNode {
  using Minter = TypeGraph;
};

// A node is a member of a family, whatever its index (a reference reaches
// the same members at every application), or an array of mutable memory;
// an edge goes from a member to what its constructors' fields name, and
// from an array to what its element names, each through grades and the
// elements of value arrays. Nodes are numbered as the module's walk meets
// them, so the numbering is the module's content alone.
class TypeGraph {
public:
  explicit TypeGraph(mlir::Operation *module);

  bool isInvalidated(const mlir::AnalysisManager::PreservedAnalyses &pa) const {
    return !pa.isPreserved<TypeGraph>();
  }

  // How many nodes there are.
  unsigned size() const { return static_cast<unsigned>(types.size()); }
  // The type of a node: an application of the member, the first the walk
  // met, or the array.
  mlir::Type type(unsigned at) const { return types[at]; }
  bool isArray(unsigned at) const { return llvm::isa<mlir::MemRefType>(types[at]); }

  // The sets of types that reach one another through an array: each
  // component that is a cycle with an array in it.
  llvm::SmallVector<llvm::SmallVector<unsigned>> knots() const;
  // The cycle of `component` through its array `array`, by a shortest path:
  // from what the array holds back to the array, and to what it holds again.
  llvm::SmallVector<unsigned> cycle(unsigned array, llvm::ArrayRef<unsigned> component) const;

private:
  using Node = Id<TypeNode>;

  // A member's node is keyed by its group and position; an array's by its
  // type.
  using Key = std::pair<mlir::Attribute, uint64_t>;

  unsigned insert(mlir::Type type);
  // The nodes a field or an element of `type` names, inserted as met.
  void named(mlir::Type type, llvm::SmallVectorImpl<unsigned> &out);

  // Every node's type, sized by the program, in the footprint's storage.
  footprint::Vector<mlir::Type> types;
  llvm::DenseMap<Key, unsigned> index;
  std::optional<Csr<TypeNode>> graph;
  std::optional<Partition<TypeNode>> parts;
};

} // namespace idr

#endif // IDR_IR_TYPEGRAPH_H
