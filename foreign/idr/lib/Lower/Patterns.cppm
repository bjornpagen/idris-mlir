// idr.lower:patterns: phase 2 of idr-lower, the conversion patterns of
// each idr op and type, with the runtime and the layouts they lower with.
export module idr.lower:patterns;

import idr.mlir;
import idr.layout;

import :arrays;
import :bigs;
import :cells;
import :counting;
import :fields;
import :runtime;
import :runtimeCalls;
import :scalars;
import :strings;

using namespace mlir;

export namespace idr::lower {

// Phase 2: the patterns that convert each idr op and type. Those of
// closures are not among them (:closures).
void populatePatterns(RewritePatternSet &patterns, const TypeConverter &converter,
                      layout::Layouts &layouts, Runtime &runtime, const Fields &fields) {
  populateCountingPatterns(patterns, converter, layouts, runtime, fields);
  populateBigPatterns(patterns, converter, layouts, runtime);
  populateArrayPatterns(patterns, converter, layouts, runtime);
  populateStringPatterns(patterns, converter, layouts, runtime);
  populateCellPatterns(patterns, converter, layouts, runtime);
  populateScalarPatterns(patterns, converter, layouts, runtime);
  populateRuntimeCallPatterns(patterns, converter, layouts, runtime);
}

} // namespace idr::lower
