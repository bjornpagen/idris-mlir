// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-bufferize's units share: the one buffer type of a cell, the
// buffer of a tensor where it is a whole cell, the buffers a release gives
// away and what may touch them after it, and the program made ready for
// the analysis. Read only by idr-bufferize's own units.
#ifndef IDR_TRANSFORMS_BUFFERIZEMODELS_H
#define IDR_TRANSFORMS_BUFFERIZEMODELS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/PatternMatch.h"

#include "llvm/ADT/EquivalenceClasses.h"

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

// The tensor values of a program that may share one buffer: every aliasing
// relation the models declare, followed both ways, before the analysis
// decides any of them. Made once, by `prepare`, and read by every question
// of a release, never closed again per question.
class AliasClasses {
public:
  AliasClasses(mlir::Operation *program, const mlir::bufferization::BufferizationOptions &options);

  // The values that may share `value`'s buffer, `value` among them.
  llvm::iterator_range<llvm::EquivalenceClasses<mlir::Value>::member_iterator>
  sharers(mlir::Value value) const;

private:
  llvm::EquivalenceClasses<mlir::Value> classes;
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

// The program made ready for any analysis: every tensor.empty has one use;
// a use that writes, without reading, a buffer a release gave away, and may
// run after the release, writes a tensor.empty of its own; and a fresh
// destination a generating op places elements that hold references into
// is an allocation empty-tensor elimination never makes a slice of another
// array, whose slots hold elements a placement would not release.
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
