// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-vectorize: the loops over arrays computed on the target's vector
// lanes, a tile at a time, one function at a time.
#ifndef IDR_TRANSFORMS_VECTORIZE_H
#define IDR_TRANSFORMS_VECTORIZE_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRVECTORIZE
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_VECTORIZE_H
