// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- StructureLoops.h - Pure loops over tensors as linalg ops -----------===//
//
// idr-structure-loops chooses a loop's form by its body's effects. The
// frontend writes each array loop's sequential meaning in scf and tensor;
// once defunctionalization and the optimizer have made every body final, a
// loop whose body only computes is made a linalg op, whose parallel
// dimensions say that order is not observed, and every other loop stays in
// order. A fold becomes a reduction only where its combiner is one
// associative and commutative integer op, since a reduction iterator means
// any order. The pass recognizes exactly the shapes the frontend writes: a
// small inverse of a small emitter, not a general loop recognizer.
//
// One matcher decides, for the pass and for idr-expect alike: planAt reads a
// loop into a Plan, build makes the linalg op the plan names.
//
//===----------------------------------------------------------------------===//

#ifndef IDR_TRANSFORMS_STRUCTURELOOPS_H
#define IDR_TRANSFORMS_STRUCTURELOOPS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/AffineMap.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr {
#define GEN_PASS_DECL_IDRSTRUCTURELOOPS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::structure {

// Whether idr-structure-loops rewrites `loop`, an scf.for: a nest it makes
// one linalg op, or a fold it makes a reduction. False for any other op.
bool structurable(mlir::Operation *loop);

// What a loop becomes.
enum class Form {
  // A nest that writes every element of its destination: one parallel op.
  Parallel,
  // A nest whose element is a fold with one integer op for its combiner:
  // one op, the nest's dimensions parallel and the fold's a reduction.
  ReduceUnder,
  // A nest whose element is any other fold over a bound fixed outside the
  // nest: the fold's loop around one parallel op over the nest, each
  // element combined in index order.
  Interchange,
  // A fold with one integer op for its combiner, under no nest that takes
  // it: one reduction op.
  Reduce,
};

// A read of a tensor from outside that becomes an input of the op, at the
// map from the op's dimensions to the read's indices.
struct Read {
  mlir::tensor::ExtractOp op;
  mlir::AffineMap map;
};

// A loop read as the linalg op it becomes. The values it names are the
// loop's own; build clones from them.
struct Plan {
  Form form = Form::Parallel;
  // The nest's loops, outermost first; none for a lone fold.
  llvm::SmallVector<mlir::scf::ForOp> nest;
  // The tensor the nest writes every element of: its outermost loop's init.
  mlir::Value destination;
  // The fold whose result the nest inserts, or the lone fold.
  mlir::scf::ForOp fold;
  // The innermost body's read of the destination at the insert's indices,
  // which the op's output element stands for, or null.
  mlir::tensor::ExtractOp element;
  // The reads that become inputs.
  llvm::SmallVector<Read> reads;
  // The nest's ops the body needs, in program order: those between its
  // loops, then those of its innermost body; never the insert, the fold, the
  // element or a read.
  llvm::SmallVector<mlir::Operation *> clones;
  // The nest's ops the fold's init needs, in program order, where the init
  // is computed per element (ReduceUnder, Interchange).
  llvm::SmallVector<mlir::Operation *> initClones;
};

// The plan of the loop rooted at `loop`, or none: nests are tried as
// ReduceUnder, Interchange, then Parallel; a loop that roots no nest as a
// lone fold.
std::optional<Plan> planAt(mlir::scf::ForOp loop);

// Builds the op `plan` names before its root loop, and gives the value that
// replaces the root loop's result.
mlir::Value build(mlir::RewriterBase &rewriter, Plan &plan);

} // namespace idr::structure

#endif // IDR_TRANSFORMS_STRUCTURELOOPS_H
