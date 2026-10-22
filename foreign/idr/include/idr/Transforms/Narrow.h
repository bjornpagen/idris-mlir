// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Integers computed in fewer bits where an analysis proves they fit.
//
// idr-narrow makes the bigs and naturals that fit a small plain i64 words,
// after versioning, across the module, each loop whose natural only
// descends; then idr-narrow-words, the word rewrite, runs per function on
// its own solve under the program's Ranges, which idr-narrow holds for it
// (the bounds of values, Facts; the values carried round loops and out of
// merges, the joints; the ops, the words). idr-narrow-lanes makes the integer lanes of
// a vectorized loop compute in 32 bits under a runtime bound on its sizes,
// found on a copy of the loop (Copy) whose ops' widths it reads.
#ifndef IDR_TRANSFORMS_NARROW_H
#define IDR_TRANSFORMS_NARROW_H

#include "idr/Analysis/Ranges.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Pass/Pass.h"

#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SetVector.h"

#include <cstdint>
#include <memory>

namespace idr {
#define GEN_PASS_DECL_IDRNARROW
#define GEN_PASS_DECL_IDRNARROWWORDS
#define GEN_PASS_DECL_IDRNARROWLANES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::narrow {

// Whether `type` is a big or a natural, under any grade.
bool isBig(mlir::Type type);

// The bounds of values: the analysis's, and those of the values the pass
// makes, which stand for values it analysed. One per function, over its
// own solve, whether its loops are versioned or its words rewritten;
// nothing it learns outlives the run. The passes that read it run on a counted program (the
// owned stage), where every value that holds references is graded.
class Facts {
public:
  explicit Facts(const Ranges::Solved &analysis) : analysis(analysis) {}

  // Whether the big `value` holds a reference of its own, which a word
  // taking its place in a consuming use leaves it to drop: its grade says.
  bool owned(mlir::Value value) const;
  // Whether `value` is a view: it holds references, and none of its own.
  bool borrowed(mlir::Value value) const;

  ranges::Bounds of(mlir::Value value) const;
  bool fits(mlir::Value value) const { return isBig(value.getType()) && of(value).fits(); }
  // Nothing among `values` is negative.
  bool nonNegative(mlir::ValueRange values) const;

  // The word of the big `value`: the integer it was made of, when it was,
  // or its value converted.
  mlir::Value word(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value);
  // The big of type `type` whose value is `word`, with the bounds `bounds`,
  // which prove it small: it holds no reference, so counting skips it.
  mlir::Value big(mlir::OpBuilder &b, mlir::Location loc, mlir::Type type, mlir::Value word,
                  ranges::Bounds bounds);

  // Whether `op` is a conversion made here, which the folds that pair
  // conversions take, and which is never narrowed again.
  bool made(mlir::Operation *op) const { return conversions.contains(op); }

private:
  void convert(mlir::Operation *op) { conversions.insert(op); }

  const Ranges::Solved &analysis;
  llvm::DenseMap<mlir::Value, ranges::Bounds> madeBounds;
  llvm::DenseSet<mlir::Operation *> conversions;
};

// The versioning of each scf.while whose natural only descends; adds the
// loops versioned to `versioned`.
void populateVersionPatterns(mlir::RewritePatternSet &patterns, Facts &facts,
                             uint64_t &versioned);
// The joints (loops and merges) whose carried bigs all fit made words; adds
// the values made words to `carried`.
void populateJointPatterns(mlir::RewritePatternSet &patterns, Facts &facts, uint64_t &carried);
// The ops whose bigs all fit made ops on words; adds the ops rewritten to
// `narrowed`.
void populateWordPatterns(mlir::RewritePatternSet &patterns, Facts &facts, uint64_t &narrowed);

// Whether `loop` is vectorized, as its ops say.
bool isVectorized(mlir::scf::ForOp loop);
// The values `loop` reads from outside it, in the order of their first use.
llvm::SetVector<mlir::Value> inputsOf(mlir::scf::ForOp loop);
// Whether `value` is one the version tests.
bool testable(mlir::Value value);
// Whether a word of `range` fits a signed 32-bit one.
bool fits32(const mlir::ConstantIntRanges &range);

// What an op computes on, the one answer the pass and its property
// (narrowed-lanes) read: for an elementwise op that is no cast and no
// select, the widest integer among its operand and result types, in bits,
// and whether it computes on lanes (one of them is a vector); none, {0,
// false}, for any other. A cast or a select only moves lanes, and costs the
// same at any width.
struct LaneWidth {
  unsigned bits;
  bool lanes;
};
LaneWidth laneWidth(mlir::Operation *op);
// The ops of `root` that only combine into a vector a loop in it carries
// round: each elementwise op the loop's iteration argument of vector type
// reaches whose results go only to one another and to the yield that
// carries that argument. Their width is the program's, as a sum is as wide
// as the program made it, so no bound on the sizes makes them fit, and
// they are no lane the narrowing is for.
llvm::DenseSet<mlir::Operation *> accumulations(mlir::Operation *root);
// Whether `loop` computes on lanes of integers wider than 32 bits outside
// its accumulations.
bool computesWideLanes(mlir::scf::ForOp loop);

// Whether `loop` runs at most once, as upstream's value bounds see its
// bounds.
bool runsAtMostOnce(mlir::scf::ForOp loop);

// The copy of a loop in a scratch module: a function of the values the
// loop reads from outside, each testable one behind arith.minui of itself
// and the bound, a constant the trials set. The copy owns the scratch
// module, which is under no op of the program, and is made whole.
class Copy {
public:
  // The copy of `loop`, which reads `inputs` from outside.
  static Copy of(mlir::Location loc, mlir::scf::ForOp loop,
                 const llvm::SetVector<mlir::Value> &inputs);

  // Sets the bound to 2^exponent.
  void bound(unsigned exponent);
  // The analysis of the copy with the bound 2^exponent, which it sets;
  // failure when the solver fails, which is an internal error.
  mlir::FailureOr<std::unique_ptr<mlir::DataFlowSolver>> analyse(unsigned exponent);
  // Whether, under `solver`'s analysis, every op of the copied loop that
  // computes on integers wider than 32 bits fits 32 bits.
  bool fits(mlir::DataFlowSolver &solver);
  // Narrows the copy under `solver`'s analysis.
  void narrow(mlir::DataFlowSolver &solver);
  // Clones the copy's body at `b`, its arguments standing for the inputs
  // they copy again.
  void cloneInto(mlir::OpBuilder &b);

private:
  Copy(mlir::OwningOpRef<mlir::ModuleOp> module, mlir::func::FuncOp function,
       mlir::scf::ForOp copy, llvm::SmallVector<mlir::Value> arguments,
       llvm::MapVector<mlir::Type, mlir::Value> bounds)
      : module(std::move(module)), function(function), copy(copy),
        arguments(std::move(arguments)), bounds(std::move(bounds)) {}

  mlir::OwningOpRef<mlir::ModuleOp> module;
  mlir::func::FuncOp function;
  // The copied loop, after the stand-ins.
  mlir::scf::ForOp copy;
  // The inputs the function's arguments stand for, in order: every input
  // but a constant, which the copy holds a copy of.
  llvm::SmallVector<mlir::Value> arguments;
  // The bound: one constant per type of input tested.
  llvm::MapVector<mlir::Type, mlir::Value> bounds;
};

} // namespace idr::narrow

#endif // IDR_TRANSFORMS_NARROW_H
