// The two phases of idr-lower.
#pragma once

#include "Lower/Runtime.h"

#include "mlir/Transforms/DialectConversion.h"

namespace idr::lower {

// Phase 1, on idr types: idr.match becomes idr.tag and
// scf.index_switch, whose cases read their constructor's fields;
// idr.match_lit becomes scf.index_switch on an integer and a chain of scf.if
// on string or big comparisons. A region that ends in ub.unreachable (after
// idr.crash) yields poison instead, which the crash before it makes
// unreachable. The structural conversion of scf then takes the types apart.
void lowerMatches(mlir::ModuleOp module);

// Phase 2: the patterns that convert each idr op and type.
void populatePatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                      Layouts &layouts, Runtime &runtime);

} // namespace idr::lower
