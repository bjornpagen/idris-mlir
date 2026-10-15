// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-bufferize's units share: the one buffer type of a cell, the
// buffer of a tensor at a place that holds a whole cell, the buffers a
// release gives away and what may touch them after it, the test of a link
// of a linear thread, and the program made ready for the analysis. Read
// only by idr-bufferize's own units.
#ifndef IDR_TRANSFORMS_BUFFERIZEMODELS_H
#define IDR_TRANSFORMS_BUFFERIZEMODELS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/PatternMatch.h"

#include "llvm/ADT/SetVector.h"

namespace idr::bufferize {

// The buffer of a tensor of type `type` where it is a whole cell: the
// tensor's shape and element, the identity layout, no memory space. Every
// buffer that crosses a call, enters a linear type or is stored in a cell
// has it, so no model reads a callee or a declaration for a layout.
mlir::MemRefType bufferType(mlir::RankedTensorType type);

// bufferType of the tensor `value`, as the interface returns a buffer type.
mlir::bufferization::BufferLikeType cellType(mlir::Value value);

// A type a cell holds, after bufferization: a ranked tensor's cell buffer,
// any other type itself. A linear tensor is no tensor here; the pass's
// retyping changes it with every other type that holds one.
mlir::Type heldType(mlir::Type type);

// The buffer of the tensor `value` as a whole cell: its buffer, reallocated
// and copied where its layout is not the cell's (a slice).
mlir::FailureOr<mlir::Value> cellBuffer(mlir::RewriterBase &rewriter, mlir::Value value,
                                        const mlir::bufferization::BufferizationOptions &options,
                                        const mlir::bufferization::BufferizationState &state);

// The values that may share the buffer of the tensor `value`: those its
// aliasing relations reach, both ways, whatever the analysis decides. No
// function is summarized here, so a call may return any operand it is given.
llvm::SetVector<mlir::Value> sharers(mlir::Value value,
                                     const mlir::bufferization::BufferizationOptions &options);

// Whether `later` may run after `earlier` while `value`, which both use, is
// still the instance `earlier` used: on a path from one to the other, or
// again around a loop that does not define `value` anew.
bool mayRunAfter(mlir::Operation *later, mlir::Operation *earlier, mlir::Value value,
                 const mlir::bufferization::BufferizationOptions &options);

// Whether `operand` is a release: its buffer outlives the op in a place the
// analysis does not see, a cell's field, a linear thread, or a callee, which
// may keep it in either. The op writes it and no result of the op is it, or
// the op is a call.
bool isRelease(mlir::OpOperand &operand, const mlir::bufferization::AnalysisState &state);

// Whether the idr.lin.enter that releases the tensor `released` is a link
// of a linear thread: every buffer the tensor may be is one an idr.lin.use
// began, through the destinations of the writes between them, and nothing
// reads or writes that buffer after the entry. It reads only aliasing and
// positions, which the models answer before the analysis decides anything,
// so every analysis of one program finds the same links.
bool isLink(mlir::OpOperand &released, const mlir::bufferization::BufferizationOptions &options);

// The program made ready for any analysis: every tensor.empty has one use,
// and a use that writes, without reading, a buffer a release gave away, and
// may run after the release, writes a tensor.empty of its own.
void prepare(mlir::Operation *program, const mlir::bufferization::BufferizationOptions &options);

// Attach the models, each family from its unit.
void attachLinearModels(mlir::MLIRContext *ctx);
void attachDataModels(mlir::MLIRContext *ctx);
void attachTieShapeModel(mlir::MLIRContext *ctx);
void attachPoisonModel(mlir::MLIRContext *ctx);

} // namespace idr::bufferize

#endif // IDR_TRANSFORMS_BUFFERIZEMODELS_H
