// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-stack: the cells that never leave their frame, put on the stack,
// a step of idr-rc (Ownership.h).
#ifndef IDR_TRANSFORMS_STACK_H
#define IDR_TRANSFORMS_STACK_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRRCSTACK
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_STACK_H
