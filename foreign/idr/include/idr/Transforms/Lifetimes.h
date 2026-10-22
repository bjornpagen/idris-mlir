// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-lifetimes: the decide step that puts each cell it can prove in a
// lifetime, born decided: every opener, kind and slot it writes is final.
#ifndef IDR_TRANSFORMS_LIFETIMES_H
#define IDR_TRANSFORMS_LIFETIMES_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRLIFETIMES
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_LIFETIMES_H
