// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-effects: what each function and each call may do, written on the
// idr.func and the idr.call as their own `effects`.
#ifndef IDR_TRANSFORMS_EFFECTS_H
#define IDR_TRANSFORMS_EFFECTS_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDREFFECTS
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_EFFECTS_H
