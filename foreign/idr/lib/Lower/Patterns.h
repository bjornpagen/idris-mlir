// The conversion patterns of idr-lower (docs/architecture/10-lowering.md).
#pragma once

#include "Lower/Layout.h"
#include "Lower/Runtime.h"

#include "mlir/Transforms/DialectConversion.h"

namespace idr::lower {

// What the patterns share: the layouts and the runtime of the module. The
// pass owns it for the whole conversion.
struct Context {
  Layouts &layouts;
  const Runtime &runtime;
};

// Adds the patterns that lower each idr op.
void populatePatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                      Context &state);

} // namespace idr::lower
