// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-bufferize: every array value of the program put in a buffer, in
// place wherever the program allows, by One-Shot Bufferize on the whole
// program, before counting. A buffer is a cell of the runtime and a copy
// the runtime's counted copy.
#ifndef IDR_TRANSFORMS_BUFFERIZE_H
#define IDR_TRANSFORMS_BUFFERIZE_H

#include "mlir/IR/DialectRegistry.h"
#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRBUFFERIZE
#include "idr/Transforms/Passes.h.inc"

namespace bufferize {

// The bufferization models of the idr ops and types that hold tensors,
// upstream's own for idr.func, idr.call and idr.return, and of ub.poison,
// which upstream gives none.
void registerModels(mlir::DialectRegistry &registry);

} // namespace bufferize
} // namespace idr

#endif // IDR_TRANSFORMS_BUFFERIZE_H
