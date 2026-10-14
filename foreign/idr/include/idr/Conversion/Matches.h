// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Phase 1 of idr-lower: matches become scf, still on idr types.

#ifndef IDR_CONVERSION_MATCHES_H
#define IDR_CONVERSION_MATCHES_H

#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"

namespace idr::conversion {

// idr.match becomes idr.tag and scf.index_switch, whose cases read their
// constructor's fields; idr.match_lit becomes scf.index_switch on an integer
// and a chain of scf.if on string or big comparisons. A region that ends in
// ub.unreachable (after idr.crash) yields poison instead, which the crash
// before it makes unreachable. The structural conversion of scf then takes
// the types apart. The declarations are read from `symbols`, the module's.
// Applied by the walk driver, which visits a region before its op: nested
// matches lower first, and the bodies move whole.
void populateMatchPatterns(mlir::RewritePatternSet &patterns, mlir::SymbolTable &symbols);

} // namespace idr::conversion

#endif // IDR_CONVERSION_MATCHES_H
