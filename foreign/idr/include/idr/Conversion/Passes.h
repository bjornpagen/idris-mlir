// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The lowering's passes: idr-lower, which declares every runtime function
// and makes every static datum once and takes each function out of the idr
// dialect; idr-entry; and idr-tail-calls.
#ifndef IDR_CONVERSION_PASSES_H
#define IDR_CONVERSION_PASSES_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRLOWER
#define GEN_PASS_DECL_IDRENTRY
#define GEN_PASS_DECL_IDRTAILCALLS
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_CONVERSION_PASSES_H
