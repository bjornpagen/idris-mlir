// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-identity, a step of idr-optimize's inner pipeline (InnerPasses.td):
// every call of a function that gives back one of its arguments, made that
// argument.
#ifndef IDR_TRANSFORMS_IDENTITY_H
#define IDR_TRANSFORMS_IDENTITY_H

#include "mlir/Pass/Pass.h"

#include <memory>

namespace idr::optimize {

class ReadySet;

// The step for one run of idr-optimize: it reads what `set` solved for
// each component, and counts the calls it rewrites into `calls`.
std::unique_ptr<mlir::Pass> createIdentity(const ReadySet &set, mlir::Pass::Statistic &calls);

} // namespace idr::optimize

#endif // IDR_TRANSFORMS_IDENTITY_H
