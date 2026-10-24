// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The lowering of the control-flow ops, in idr-lower's three steps, and
// what is told of loops before them. Blocks appear only in the last, in one
// conversion with upstream's scf patterns.

#ifndef IDR_CONVERSION_MATCHES_H
#define IDR_CONVERSION_MATCHES_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Transforms/DialectConversion.h"

namespace idr::conversion {

// Phase 1, on idr types: idr.data.match becomes idr.data.tag and
// scf.index_switch, each case taking the scrutinee and the forwarded values
// at their refined types, which have no run-time form; a match left with
// one region tests no tag. idr.lit.match on a word the target's index holds
// becomes scf.index_switch over the word's index cast, its default handed
// the scrutinee; on any other carrier, a chain of scf.if on each key's
// comparison by the carrier's equality (a double's ordered). The lifetime a
// match states for what it makes has no run-time form either, and goes
// with it. These are the only scf.index_switch ops a program holds.
// A case that jumps to an enclosing join point or never ends keeps its
// terminator, which upstream's scf.index_switch and scf.if hold. Applied
// by the walk driver, which visits a region before its op: nested matches
// lower first, and the bodies move whole.
void populateMatchPatterns(mlir::RewritePatternSet &patterns);

// Phase 2, the conversion of types: idr.join, idr.loop, idr.jump and the
// idr.yield that ends a join point's region take the converted types of
// their results, parameters and arguments, one value becoming its
// components, beside upstream's structural conversion of scf; each is
// legal once its types are. A jump is converted in place, so it keeps what
// it carries for LLVM. A join point's op drops the lifetime it states,
// which nothing lowered reads. idr.may_loop, read before phase 0, goes.
void populateJoinTypeConversions(const mlir::TypeConverter &converter,
                                 mlir::RewritePatternSet &patterns,
                                 mlir::ConversionTarget &target);

// Phase 3: the join points become blocks in one conversion with upstream's
// scf patterns, so a jump nested in a match, which upstream's lowering of
// scf.index_switch and scf.if leaves in place, is a branch by then: each
// region's blocks move into the function, each jump a cf.br to its join
// region's entry, each yield a cf.br to what follows the op. An
// irreducible group lowers as any other, with no run-time selector. A
// jump's annotation that its loop makes progress (tellProgress) goes on
// the branch it becomes. The conversion is the same for every function, so
// it is made once, before any function is lowered, and every function's
// lowering reads it, unwritten, from whichever worker runs it.
struct ControlFlowLowering {
  explicit ControlFlowLowering(mlir::MLIRContext &context);

  // Upstream's own target for scf, with the join points' ops illegal
  // beside scf's.
  mlir::ConversionTarget target;
  // Upstream's scf patterns and the join points'.
  mlir::FrozenRewritePatternSet patterns;
  // What a jump back into a loop that makes progress carries: upstream's
  // loop annotation, `mustProgress`, under its own name.
  mlir::DictionaryAttr progresses;
};

// Before phase 0, on the function as the passes left it, while it and its
// calls carry their rows: in a function whose row withholds `mustprogress`
// from LLVM, each idr.loop nothing in whose join regions withholds it (no
// op whose row does: idr.may_loop, its own or a nested loop's, or a call
// of a function that may never end) is told it makes progress, on each
// jump back, which phases 2 and 3 carry to the branch it becomes as
// upstream's loop annotation. Of any other function, its row tells LLVM
// all there is to tell of its loops.
void tellProgress(FuncOp fn, const ControlFlowLowering &lowering);

// Applies phase 3 to `root`, a function.
mlir::LogicalResult lowerControlFlow(mlir::Operation *root, const ControlFlowLowering &lowering);

} // namespace idr::conversion

#endif // IDR_CONVERSION_MATCHES_H
