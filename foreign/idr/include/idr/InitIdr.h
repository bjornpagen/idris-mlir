// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The idr dialect on a registry, as upstream's InitAllDialects.h puts its
// dialects on one: the dialect; the flow models of the upstream ops a
// module of it holds, which the verifier reads from the parse on; and the
// schedule library the pipeline's interpreter runs, built when the
// transform dialect loads. Every tool and the compiler read a module with
// a registry this has filled. Upstream's transform ops the library is
// written in are registered on the registry first: an extension applies
// in the order it was added, so the library is built only after them.
#ifndef IDR_INITIDR_H
#define IDR_INITIDR_H

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Target/Target.h"

#include "mlir/IR/DialectRegistry.h"

namespace idr {

inline void registerIdrDialects(mlir::DialectRegistry &registry) {
  registry.insert<idr::IdrDialect>();
  idr::registerFlowInterfaceExternalModels(registry);
  idr::target::registerScheduleLibrary(registry);
}

} // namespace idr

#endif // IDR_INITIDR_H
