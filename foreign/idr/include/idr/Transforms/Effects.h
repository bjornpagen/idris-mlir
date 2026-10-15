// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The passes of the two summaries. idr-effects writes what each function
// and each call of a defunctionalized module may do, as their own
// `effects`, with the code the ready set runs on each component.
// idr-constants is the last step of idr-optimize's inner pipeline: one
// function's constants, its calls' results taken from their callees'
// summaries.
#ifndef IDR_TRANSFORMS_EFFECTS_H
#define IDR_TRANSFORMS_EFFECTS_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDREFFECTS
#define GEN_PASS_DECL_IDRCONSTANTS
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_EFFECTS_H
