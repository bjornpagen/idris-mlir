// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The lowering's passes: idr-lower-runtime and idr-lower-statics, which
// declare every runtime function and make every static datum once;
// idr-lower, which takes each function out of the idr dialect; idr-entry;
// and idr-tail-calls.
#ifndef IDR_CONVERSION_PASSES_H
#define IDR_CONVERSION_PASSES_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRLOWERRUNTIME
#define GEN_PASS_DECL_IDRLOWERSTATICS
#define GEN_PASS_DECL_IDRLOWER
#define GEN_PASS_DECL_IDRENTRY
#define GEN_PASS_DECL_IDRTAILCALLS
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_CONVERSION_PASSES_H
