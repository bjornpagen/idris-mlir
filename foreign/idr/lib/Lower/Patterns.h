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

// Phase 1 too, after the matches: idr.array.generate and idr.array.fold
// become linalg.generic over the arrays (Loops.cc).
void lowerArrayLoops(mlir::ModuleOp module);

// The memref view of an array of words: the descriptor convert-to-llvm
// reads for a memref of `view`'s type, built over the cell and its length
// (Arrays.cc). Phase 2 gives it to every legal op that still holds the
// array.
mlir::Value arrayView(mlir::OpBuilder &b, mlir::Location loc, Runtime &runtime,
                      mlir::MemRefType view, mlir::Value cell, mlir::Value length);

// What the owned stage settled about the fields of the ops that count
// references, read after phase 1 and before the conversion starts, which
// replaces each op as it meets it (Counting.cc).
class Fields {
public:
  explicit Fields(mlir::ModuleOp module);

  // For a reuse of the constructor its token's take took apart: for each
  // field, whether the cell holds it already, because the reuse gives it
  // back as the take gave it. Empty for a reuse of another constructor,
  // whose cell holds none of its fields, and a new header.
  llvm::ArrayRef<bool> kept(ReuseOp reuse) const;

private:
  llvm::DenseMap<mlir::Operation *, llvm::SmallVector<bool>> keptFields;
};

// Phase 2: the patterns that convert each idr op and type.
void populatePatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                      Layouts &layouts, Runtime &runtime, const Fields &fields);

// The patterns of closures (Closures.cc). Only idr-eval's lowering meets a
// closure: it runs code before idr-defunctionalize has made every closure
// of the program a sum.
void populateClosurePatterns(mlir::RewritePatternSet &patterns,
                             const mlir::TypeConverter &converter, Layouts &layouts,
                             Runtime &runtime);

// The patterns of the ops that count references (Counting.cc).
void populateCountingPatterns(mlir::RewritePatternSet &patterns,
                              const mlir::TypeConverter &converter, Layouts &layouts,
                              Runtime &runtime, const Fields &fields);

// The patterns of arrays (Arrays.cc).
void populateArrayPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                           Layouts &layouts, Runtime &runtime);

// The patterns of bigs and naturals, whose small case is inline (Bigs.cc).
void populateBigPatterns(mlir::RewritePatternSet &patterns, const mlir::TypeConverter &converter,
                         Layouts &layouts, Runtime &runtime);

// The string builders over lists (Strings.cc).
void populateStringPatterns(mlir::RewritePatternSet &patterns,
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
