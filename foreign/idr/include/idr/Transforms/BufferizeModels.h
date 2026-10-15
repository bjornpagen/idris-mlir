// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What idr-bufferize's models share: the one buffer type of a cell, the
// buffer of a tensor at a place that holds a whole cell, what the module
// analysis knows of a call's callee, and the test of a link of a linear
// thread. Read only by idr-bufferize's own units.
#ifndef IDR_TRANSFORMS_BUFFERIZEMODELS_H
#define IDR_TRANSFORMS_BUFFERIZEMODELS_H

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/FunctionInterfaces.h"

namespace idr::bufferize {

// The buffer of a tensor of type `type` where it is a whole cell: the
// tensor's shape and element, the identity layout, no memory space. Every
// buffer that crosses a call, enters a linear type or is stored in a cell
// has it, so no model reads a callee or a declaration for a layout.
mlir::MemRefType bufferType(mlir::RankedTensorType type);

// bufferType of the tensor `value`, as the interface returns a buffer type.
mlir::bufferization::BufferLikeType cellType(mlir::Value value);

// A type at a function's boundary after bufferization: a ranked tensor's
// cell buffer, any other type itself. A linear tensor is no tensor here;
// the pass's retyping changes it with every other type that holds one.
mlir::Type boundaryType(mlir::Type type);

// The buffer of the tensor `value` as a whole cell: its buffer, reallocated
// and copied where its layout is not the cell's (a slice).
mlir::FailureOr<mlir::Value> cellBuffer(mlir::RewriterBase &rewriter, mlir::Value value,
                                        const mlir::bufferization::BufferizationOptions &options,
                                        const mlir::bufferization::BufferizationState &state);

// The function `call` calls, when the analysis asking is the module
// analysis and it has finished that function; null otherwise: under a
// nested analysis of one function, which may not read a sibling, and for a
// callee on a cycle of calls with the caller, which the module analysis
// does not summarize.
mlir::FunctionOpInterface analyzedCallee(CallOp call,
                                         const mlir::bufferization::AnalysisState &state);

// Whether `enter` is a link of a linear thread: its operand's buffer is one
// an idr.lin.use began, directly or through the destinations of the writes
// between them. It reads only aliasing, which the models answer before the
// analysis decides anything.
bool isLink(LinEnterOp enter, const mlir::bufferization::AnalysisState &state);

// Attach the models, each family from its unit.
void attachFunctionModels(mlir::MLIRContext *ctx);
void attachLinearModels(mlir::MLIRContext *ctx);
void attachDataModels(mlir::MLIRContext *ctx);
void attachTieShapeModel(mlir::MLIRContext *ctx);
void attachPoisonModel(mlir::MLIRContext *ctx);

} // namespace idr::bufferize

#endif // IDR_TRANSFORMS_BUFFERIZEMODELS_H
