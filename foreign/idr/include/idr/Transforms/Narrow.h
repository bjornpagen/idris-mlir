// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Integers computed in fewer bits where an analysis proves they fit.
//
// idr-narrow makes the bigs and naturals that fit a small plain i64 words,
// after versioning, across the module, each loop whose natural only
// descends; then idr-narrow-words, the word rewrite, runs per function on
// its own solve under the program's Ranges, which idr-narrow holds for it
// (the function's values numbered and bounded, Facts; the values carried
// round loops and out of merges, the joints, Carried.cpp; the ops, the
// words, Ops.cpp). idr-narrow-lanes makes the integer lanes of a
// vectorized loop compute in 32 bits under a runtime bound on its sizes,
// found on a copy of the loop (Copy) whose ops' widths it reads.
#ifndef IDR_TRANSFORMS_NARROW_H
#define IDR_TRANSFORMS_NARROW_H

#include "idr/Analysis/Ranges.h"
#include "idr/Analysis/Solver/Extraction.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ranges.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "mlir/Pass/Pass.h"

#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SetVector.h"

#include <cstdint>
#include <memory>
#include <utility>
#include <variant>

namespace idr {
#define GEN_PASS_DECL_IDRNARROW
#define GEN_PASS_DECL_IDRNARROWWORDS
#define GEN_PASS_DECL_IDRNARROWLANES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

namespace idr::narrow {

// Whether `type` is a big or a natural, under any grade.
bool isBig(mlir::Type type);

// The bounds of `value` as `analysis` found them: the range its type
// proves where the analysis lost it, none where it never reached it, and
// the program's poison, which may be taken to be any value, a small. The
// one read of a value's bounds. The passes that read it run on a counted
// program (the owned stage), where every value that holds references is
// graded.
ranges::Bounds boundsOf(const Ranges::Solved &analysis, mlir::Value value);
// Whether the big `value` holds a reference of its own, which a word
// taking its place in a consuming use leaves it to drop: its grade says.
bool owned(mlir::Value value);
// Whether `value` is a view: it holds references, and none of its own.
bool borrowed(mlir::Value value);

// The versioning of each scf.while whose natural only descends, under
// `analysis`; adds the loops versioned to `versioned`.
void populateVersionPatterns(mlir::RewritePatternSet &patterns, const Ranges::Solved &analysis,
                             uint64_t &versioned);

//===----------------------------------------------------------------------===//
// The word rewrite
//===----------------------------------------------------------------------===//

// idr-narrow-words numbers its function's values in one walk, decides on
// those numbers which webs of carried values become words, and then
// rewrites in one pass over the ops the walk met, in its order: each joint
// by the webs' decisions, each other op that takes or gives a big by the
// pattern MLIR finds for it, which decides on the numbers of what the op
// took and gave as the walk met it. So nothing the rewrite makes is ever
// asked about: the facts of every value it stands in for are the numbered
// value's.

class Facts;

// A value of the function as its solve saw it, numbered by the body's one
// numbering before anything is rewritten.
struct Analysed {
  using Minter = solver::Numbering<Analysed>;
};
using ValueId = Id<Analysed>;

// What a value is, as the walk numbered it: no big, a big made of a word
// (an idr.big.small, whose word is its operand), or any other big.
enum class Carrier : std::uint8_t { NoBig, SmallBig, Big };

// One class of a joint: the operands it forwards, each once, and the
// values they become there, each once, in the order the joint forwards
// them; ranges of the facts' passes and inputs.
struct Carry {
  std::uint32_t passes, passesEnd, inputs, inputsEnd;
};

// An operand a joint forwards: the use, the value it held when the
// function was numbered, and one value it becomes, which is in its class.
struct Pass {
  mlir::OpOperand *operand;
  ValueId from;
  ValueId into;
};

// The steps of the rewrite, in the walk's order. A joint is met twice:
// entering it, before its regions, the arguments of its regions that a web
// carries become words, so everything inside reads them as the bigs of
// words; leaving it, the results it carries become words and what it
// forwards is passed as one. Entering, its regions' big arguments are a
// range of the facts' own values, those of its classes first in the
// classes' order; leaving, its classes are a range of the facts' carries,
// and its big results no class of its own holds, which only a value
// forwarded from deeper inside it reaches, a range of its own values.
struct Enter {
  mlir::Operation *joint;
  std::uint32_t own, ownEnd;
};
struct Leave {
  mlir::Operation *joint;
  std::uint32_t carries, carriesEnd, own, ownEnd;
};
// Any other op that takes or gives a big, with the ids of its operands and
// then of its results from `ids` on in the facts' ids.
struct Word {
  mlir::Operation *op;
  std::uint32_t ids;
};
using Step = std::variant<Enter, Leave, Word>;

// One function's facts, over its own solve: its values numbered, what each
// is and its bounds, the webs of what its joints carry, and the steps of
// its rewrite. Nothing it learns outlives the run.
class Facts {
public:
  // The body's one numbering numbers `fn`'s values; one walk records its
  // steps; then the bounds of every value a step reads are read off
  // `analysis` once, and the webs are joined.
  Facts(FuncOp fn, const Ranges::Solved &analysis);

  Count<ValueId> count() const { return values.size(); }
  // The value numbered `v`, as it was: the rewrite retypes some and erases
  // others, so only the rewrite's own steps read it, each before it
  // changes the value.
  mlir::Value value(ValueId v) const { return values[v]; }
  ranges::Bounds bounds(ValueId v) const { return bounded[v]; }
  Carrier carrier(ValueId v) const { return carriers[v]; }
  // Whether `v` is a big that fits a small.
  bool fits(ValueId v) const { return carriers[v] != Carrier::NoBig && bounded[v].fits(); }
  // The web `v` is in: one value of it, the same for every member. A web
  // is the values one joint's operand becomes, joined across every joint,
  // so a value one joint forwards into another's region is decided once.
  ValueId web(ValueId v) const { return webs[v]; }

  llvm::ArrayRef<Step> steps() const { return walked; }
  llvm::ArrayRef<Carry> carries(std::uint32_t first, std::uint32_t end) const {
    return llvm::ArrayRef<Carry>(classes).slice(first, end - first);
  }
  llvm::ArrayRef<Pass> passes(const Carry &carry) const {
    return llvm::ArrayRef<Pass>(passed).slice(carry.passes, carry.passesEnd - carry.passes);
  }
  llvm::ArrayRef<ValueId> inputs(const Carry &carry) const {
    return llvm::ArrayRef<ValueId>(carried).slice(carry.inputs, carry.inputsEnd - carry.inputs);
  }
  // A joint's own values: entering it, its regions' big arguments; leaving
  // it, its big results no class of its own holds.
  llvm::ArrayRef<ValueId> ownOf(const Enter &step) const { return own(step.own, step.ownEnd); }
  llvm::ArrayRef<ValueId> ownOf(const Leave &step) const { return own(step.own, step.ownEnd); }
  // The ids of `word`'s operands, then of its results.
  llvm::ArrayRef<ValueId> idsOf(const Word &word) const {
    return llvm::ArrayRef<ValueId>(numbered).slice(
        word.ids, word.op->getNumOperands() + word.op->getNumResults());
  }

  // The id of `value`, a value of the function as numbered, which the
  // rewrite kept.
  ValueId at(mlir::Value value) const { return numbering.at(value); }

private:
  llvm::ArrayRef<ValueId> own(std::uint32_t first, std::uint32_t end) const {
    return llvm::ArrayRef<ValueId>(owns).slice(first, end - first);
  }
  // The walk: records each step, in the numbering's order, a joint as it
  // enters and leaves it and any other op after the ops inside it; then
  // each id's value.
  IndexVector<ValueId, mlir::Value> walk(FuncOp fn);
  // What `joint` adds to the facts: its classes, appended to the carries;
  // the big arguments of its regions, then its big results no class of its
  // own holds, appended to the own values; their ranges.
  struct Classified {
    std::uint32_t carries, carriesEnd, arguments, argumentsEnd, results, resultsEnd;
  };
  Classified classify(mlir::Operation *joint);
  // The bounds of each value a step reads, off `analysis`.
  IndexVector<ValueId, ranges::Bounds> read(const Ranges::Solved &analysis) const;
  // Each value's web, joined over every class of every joint.
  IndexVector<ValueId, ValueId> join() const;

  // The body's one numbering, the one map keyed by an IR handle, read
  // where a question arrives by value.
  solver::Numbering<Analysed> numbering;
  footprint::Vector<Step> walked;
  footprint::Vector<Carry> classes;
  footprint::Vector<Pass> passed;
  footprint::Vector<ValueId> carried;
  footprint::Vector<ValueId> owns;
  footprint::Vector<ValueId> numbered;
  // Made once the walk has numbered every value.
  IndexVector<ValueId, mlir::Value> values;
  IndexVector<ValueId, Carrier> carriers;
  IndexVector<ValueId, ranges::Bounds> bounded;
  IndexVector<ValueId, ValueId> webs;
};

// The word of the big `value`: the integer it was made of, when it was
// (a big made of a word, or of a narrower integer), the word of the
// program's poison, or its value converted.
mlir::Value word(mlir::OpBuilder &b, mlir::Location loc, mlir::Value value);
// The big of type `type` whose value is `word`, which fits a small: it
// holds no reference, so counting skips it.
mlir::Value big(mlir::OpBuilder &b, mlir::Location loc, mlir::Type type, mlir::Value word);
// Retypes the big block argument `arg` to i64: its uses get the big of it.
void narrowArgument(mlir::RewriterBase &rewriter, mlir::BlockArgument arg);

// What is decided: the values of the webs the joints carry, before the
// rewrite (decideJoints); the results of each op made its word op, which
// it erases, as the rewrite reaches it; and every value a narrowed use
// takes the word of.
struct Decisions {
  explicit Decisions(Count<ValueId> count) : carried(count), computed(count), asked(count) {}
  BitSet<ValueId> carried, computed, asked;
};

// The webs the joints carry, each fitting web through one action
// (Carried.cpp); whether any is.
Changed decideJoints(const Facts &facts, Decisions &decided);
// A joint's part of the rewrite as the walk enters it and as it leaves it.
void enter(mlir::RewriterBase &rewriter, const Facts &facts, const Decisions &decided,
           const Enter &step);
void leave(mlir::RewriterBase &rewriter, const Facts &facts, const Decisions &decided,
           const Leave &step);

// The rewriter the word patterns are applied with: the facts and decisions
// they read, and the step the rewrite is at, whose op MLIR dispatched to
// the pattern. Only the rewrite applies them, always through this.
class WordRewriter : public mlir::PatternRewriter {
public:
  WordRewriter(mlir::MLIRContext *ctx, const Facts &facts, Decisions &decided)
      : PatternRewriter(ctx), facts(facts), decided(decided) {}

  const Facts &facts;
  Decisions &decided;
  const Word *step = nullptr;
};

// The patterns of the ops with a word form, MLIR's dispatch on them, each
// rooted at its op (Ops.cpp): every big op whose word op the ODS names
// (BigToWord), a guard, counting, and a literal match, applied as the walk
// enters it. Built once per pass.
void populateWordPatterns(mlir::RewritePatternSet &patterns);

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
// they are no lane the narrowing is for. The ops of `root` are numbered
// once, in the walk's order, the one map keyed by an IR handle, and every
// fact the search keeps about an op is a bit by its number.
class Accumulations {
public:
  explicit Accumulations(mlir::Operation *root);
  // Whether `op`, an op of `root`, is one of them.
  bool contains(mlir::Operation *op) const;

private:
  footprint::DenseMap<mlir::Operation *, std::uint32_t> number;
  footprint::Vector<mlir::Operation *> ops;
  llvm::BitVector carried;
};
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
