// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- StructureLoops.h - The array ops, lowered once ---------------------===//
//
// idr-structure-loops is the one-to-one lowering of the array language's
// generating set (idr.tabulate, idr.tabulate_io, idr.fold_last,
// idr.scan_last, idr.transpose), once every call has its final effects. Each op says how it visits its domain (getIterations); what its
// region does decides the rest. A region that does no more than compute
// and crash, over arrays of words, keeps the op's parallel dimensions
// parallel in a linalg op; every other op is an scf.for nest in its
// row-major order. The decision reads the op alone, so it is made once and
// held here, for the pass and for idr-expect alike.
//
//===----------------------------------------------------------------------===//

#ifndef IDR_TRANSFORMS_STRUCTURELOOPS_H
#define IDR_TRANSFORMS_STRUCTURELOOPS_H

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Linalg/IR/Linalg.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/AffineMap.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

namespace idr {
#define GEN_PASS_DECL_IDRSTRUCTURELOOPS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::structure {

// What an op of the generating set is lowered to.
enum class Form {
  // One linalg op over the domain, every dimension parallel: a tabulation,
  // or a transpose of words.
  Parallel,
  // One linalg op whose last dimension is a reduction: a fold whose every
  // next accumulator is one associative and commutative integer op of its
  // accumulator, which may then be combined in any order.
  Reduction,
  // The ordered dimension as an scf.for around one linalg op over the
  // frame's parallel dimensions: a fold or a scan over words whose
  // combiner is kept in index order, its frame computed on lanes.
  Interchange,
  // An scf.for nest in the op's row-major order, its region the body.
  Ordered,
};

// Whether idr-structure-loops lowers `op`: an op of the generating set or
// idr.transpose. None is left after it.
bool structurable(mlir::Operation *op);

// The form `op`, which idr-structure-loops lowers, takes. A call does what
// its own effects say.
Form formOf(mlir::Operation *op);

// A read of an array of words from outside an op, directly in its region,
// at distinct indices of the op's domain, each as large as the dimension
// of the domain it is read at: an input of the linalg op, at `map` from the
// linalg op's dimensions.
struct Read {
  mlir::tensor::ExtractOp op;
  mlir::AffineMap map;
};

// The reads of `op`'s region that become inputs of a linalg op whose
// dimensions are the domain's first `dims`.
llvm::SmallVector<Read> readsOf(mlir::Operation *op, unsigned dims);

// Replaces `op` by its form.
void lower(mlir::RewriterBase &rewriter, mlir::Operation *op, Form form);

// The forms, each replacing its op.
void lowerParallel(mlir::RewriterBase &rewriter, mlir::Operation *op);
void lowerReduction(mlir::RewriterBase &rewriter, LastAxisFoldOpInterface op);
void lowerInterchange(mlir::RewriterBase &rewriter, LastAxisFoldOpInterface op);
void lowerOrdered(mlir::RewriterBase &rewriter, mlir::Operation *op);

// What the forms share. The region of `op` moved before the rewriter's
// insertion point, its arguments `args`, the insertion point left after it:
// what its yield gives, values of the types `given`, or, where it ends in
// ub.unreachable and never returns, poison of them, which no path reaches.
// The terminator is erased.
llvm::SmallVector<mlir::Value> inlineRegion(mlir::RewriterBase &rewriter, mlir::Operation *op,
                                            mlir::ValueRange args, mlir::TypeRange given);

// The same, with the region copied, so that `op` keeps it.
llvm::SmallVector<mlir::Value> cloneRegion(mlir::OpBuilder &b, mlir::Operation *op,
                                           mlir::ValueRange args, mlir::TypeRange given);

// The sizes of the first `dims` dimensions of `op`'s domain, and sizes as
// values.
llvm::SmallVector<mlir::OpFoldResult> extentsOf(mlir::OpBuilder &b, mlir::Operation *op,
                                                unsigned dims);
llvm::SmallVector<mlir::Value> valuesOf(mlir::OpBuilder &b, mlir::Location loc,
                                        llvm::ArrayRef<mlir::OpFoldResult> sizes);

// A new array of `type`, whose dimensions the type leaves dynamic are
// sized by `dims`, which holds one size per dimension up to the last of
// those at least; the type's own sizes stand for the rest.
mlir::Value emptyOf(mlir::OpBuilder &b, mlir::Location loc, mlir::RankedTensorType type,
                    llvm::ArrayRef<mlir::OpFoldResult> dims);

// What `array` holds at `indices` of its leading dimensions, of type
// `cell`: the element, or the cell of the dimensions after them (at no
// index, the array itself).
mlir::Value readCell(mlir::OpBuilder &b, mlir::Location loc, mlir::Value array,
                     mlir::ValueRange indices, mlir::Type cell);

// `array` with `cell`, an element or a cell, at `indices` of its leading
// dimensions (at no index, the cell itself).
mlir::Value writeCell(mlir::OpBuilder &b, mlir::Location loc, mlir::Value cell, mlir::Value array,
                      mlir::ValueRange indices);

} // namespace idr::structure

#endif // IDR_TRANSFORMS_STRUCTURELOOPS_H
