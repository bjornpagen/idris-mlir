// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The passes of the two summaries. idr-effects writes what each function
// of a first-order program may do, as its `effects`, with the driver the
// ready set runs on each component. idr-constants is the last step of
// idr-optimize's inner pipeline (InnerPasses.td): one function's
// constants, its calls' results taken from their callees' summaries.
#ifndef IDR_TRANSFORMS_EFFECTS_H
#define IDR_TRANSFORMS_EFFECTS_H

#include "mlir/Pass/Pass.h"

#include <memory>

namespace idr {

#define GEN_PASS_DECL_IDREFFECTS
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

namespace idr::optimize {

class ReadySet;

// The step for one run of idr-optimize: it reads the summaries `set`
// publishes, and counts the values it replaces into `constants`.
std::unique_ptr<mlir::Pass> createConstants(const ReadySet &set,
                                            mlir::Pass::Statistic &constants);

} // namespace idr::optimize

#endif // IDR_TRANSFORMS_EFFECTS_H
