// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-demand: the promise a program can be asked to keep, checked on the
// grades idr-rc wrote.
#ifndef IDR_TRANSFORMS_DEMAND_H
#define IDR_TRANSFORMS_DEMAND_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRDEMAND
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_DEMAND_H
