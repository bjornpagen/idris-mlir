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

// Also phase 1: idr.big.pred becomes idr.big.sub of 1, which the runtime
// computes (Predecessors.cc).
void lowerPredecessors(mlir::ModuleOp module);

// Phase 2: the patterns that convert each idr op and type.
void populatePatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                      Layouts &layouts, Runtime &runtime);

// The patterns of closures (Closures.cc). Only idr-eval's lowering meets a
// closure: it runs code before idr-defunctionalize has made every closure
// of the program a sum.
void populateClosurePatterns(mlir::RewritePatternSet &patterns,
                             const mlir::TypeConverter &converter, Layouts &layouts,
                             Runtime &runtime);

// The patterns of the ops that count references (Counting.cc).
void populateCountingPatterns(mlir::RewritePatternSet &patterns,
                              const mlir::TypeConverter &converter, Layouts &layouts,
                              Runtime &runtime);

// The base of the patterns: the layouts and the runtime they lower with.
template <typename OpT>
struct IdrPattern : mlir::OpConversionPattern<OpT> {
  IdrPattern(const mlir::TypeConverter &converter, mlir::MLIRContext *ctx, Layouts &l, Runtime &r)
      : mlir::OpConversionPattern<OpT>(converter, ctx), layouts(l), runtime(r) {}
  Layouts &layouts;
  Runtime &runtime;
};

// A box's cell: count 1 and its info word, then its fields' components
// stored at their offsets.
mlir::Value buildBox(mlir::OpBuilder &b, mlir::Location loc, Layouts &layouts, Runtime &runtime,
                     CtorOp ctor, mlir::Value cell, llvm::ArrayRef<mlir::ValueRange> fields);

} // namespace idr::lower
