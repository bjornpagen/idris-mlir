// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-bufferize's units share: the one buffer type of a cell, the
// buffer of a tensor where it is a whole cell, the buffers a release gives
// away and what may touch them after it, and the program made ready for
// the analysis. Read only by idr-bufferize's own units.
#ifndef IDR_TRANSFORMS_BUFFERIZEMODELS_H
#define IDR_TRANSFORMS_BUFFERIZEMODELS_H

#include "idr/Analysis/Solver/Components.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/PatternMatch.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <utility>

namespace idr::bufferize {

// The buffer of a tensor of type `type` where it is a whole cell: the
// tensor's shape and element, the identity layout, no memory space. Every
// buffer that crosses a call, enters a grade or is stored in a cell has
// it, so no model reads a callee or a declaration for a layout.
mlir::MemRefType bufferType(mlir::RankedTensorType type);

// The buffer type of a tensor-like type where it is a whole cell: a
// tensor's cell buffer, and a graded tensor's at the same grade, so that
// the grade a type carries is the grade its buffer carries.
mlir::bufferization::BufferLikeType cellType(mlir::bufferization::TensorLikeType type);

// The buffer of the tensor `value` as a whole cell: its buffer, reallocated
// and copied where its layout is not the cell's (a slice).
mlir::FailureOr<mlir::Value> cellBuffer(mlir::RewriterBase &rewriter, mlir::Value value,
                                        const mlir::bufferization::BufferizationOptions &options,
                                        const mlir::bufferization::BufferizationState &state);

class AliasClasses;

// A value an aliasing relation names, numbered as the program's walk first
// meets it.
struct AliasedValue {
  using Minter = AliasClasses;
};

// The tensor values of a program that may share one buffer: every aliasing
// relation the models declare, followed both ways, before the analysis
// decides any of them; and the program's releases, each with the number of
// the value it gives away. Made once, by `prepare`, in one walk, and read
// by every question of a release, never closed again per question. A
// relation is an edge each way between two numbered values, so the classes
// are the components of that graph, laid out by the solver layer; the
// graph and its components are the footprint's. The walk numbers each
// value as it first meets it, by the one map keyed by an IR handle, which
// is gone when the walk ends: every question after it asks by number.
class AliasClasses {
public:
  using Node = Id<AliasedValue>;
  // A release (isRelease), and the number of the value it gives away.
  struct Release {
    mlir::OpOperand *operand;
    Node value;
  };

  AliasClasses(mlir::Operation *program, const mlir::bufferization::BufferizationOptions &options);

  // The program's releases, in the walk's order.
  llvm::ArrayRef<Release> releases() const { return released; }
  // The values that may share the buffer of the value numbered `value`, it
  // among them.
  llvm::SmallVector<mlir::Value> sharers(Node value) const;

private:
  // The graph of the relations among `program`'s values, each value
  // numbered as it is first met, and its releases.
  Csr<AliasedValue> related(mlir::Operation *program,
                            const mlir::bufferization::BufferizationOptions &options);

  // Each number's value and the releases, both made before the classes.
  footprint::Vector<mlir::Value> values;
  footprint::Vector<Release> released;
  Partition<AliasedValue> classes;
};

// Whether `later` may run after `earlier` while `value`, which both use, is
// still the instance `earlier` used: on a path from one to the other, or
// again around a loop that does not define `value` anew.
bool mayRunAfter(mlir::Operation *later, mlir::Operation *earlier, mlir::Value value,
                 const mlir::bufferization::BufferizationOptions &options);

// Whether `operand` is a release: its buffer outlives the op in a place the
// analysis does not see, a cell (bufferization.to_buffer before idr.data.con, a
// memo cell's value) or a callee, which may keep it in one. The op writes
// it and no result of the op is it, or the op is a call.
bool isRelease(mlir::OpOperand &operand, const mlir::bufferization::AnalysisState &state);

// The program made ready for any analysis: the tensor of a buffer read out
// of a cell whose grade claims its own cells unshared, which covers the
// buffer's storage, is writable; an insert of elements that hold
// references over the whole of its destination is its source; every
// tensor.empty has one use; a use that writes, without reading, a buffer a
// release gave away, and may run after the release, writes a tensor.empty
// of its own; and a fresh destination a generating op places elements that
// hold references into is an allocation empty-tensor elimination never
// makes a slice of another array, whose slots hold elements a placement
// would not release. So a buffer allocated for such elements is written
// first by an op that places all of it.
void prepare(mlir::Operation *program, const mlir::bufferization::BufferizationOptions &options);

// Attach the models, each family from its unit.
void attachGradedModels(mlir::MLIRContext *ctx);
void attachLinearModels(mlir::MLIRContext *ctx);
void attachDataModels(mlir::MLIRContext *ctx);
void attachGeneratingModels(mlir::MLIRContext *ctx);
void attachTieShapeModel(mlir::MLIRContext *ctx);
void attachPoisonModel(mlir::MLIRContext *ctx);

} // namespace idr::bufferize

#endif // IDR_TRANSFORMS_BUFFERIZEMODELS_H
