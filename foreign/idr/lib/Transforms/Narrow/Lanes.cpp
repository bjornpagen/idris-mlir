// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-narrow-lanes: the integer lanes of a vectorized loop compute in 32
// bits under a runtime bound on its index space. The vectorization
// schedule leaves a loop over an array computing on its coordinates, which
// are index, 64 bits once lowered, and on the 64-bit Int the program wrote
// from them, and the target's lanes pay for it: neither x86-64-v3 nor NEON
// has a 64-bit vector multiply, and x86-64-v3 has no int64-to-double
// conversion, so LLVM emulates the one and scalarizes the other, where
// 32-bit lanes have both. Upstream's narrowing reaches an index lane
// through index casts, as it reaches a word. Each vectorized loop that
// computes on lanes of integers wider than 32 bits, outside the
// accumulations it carries round (a sum is as wide as the program made
// it), becomes two versions: where every integer it reads from outside
// (the sizes, the tile bound) is at most B, a copy in which every integer
// op that integer range analysis proves fits 32 bits is narrowed by
// upstream's arith-int-range-narrowing; otherwise the loop as it was. A
// loop that runs at most once, as upstream's value bounds see its bounds
// (the loop of a peeled tile loop's last tile), stays as it is: its
// version would never pay for the code it adds.
//
// The bound is an SSA fact, since the analysis reads no branch condition:
// in the copy each such input stands behind arith.minui of itself and B,
// which equals it under the guard and which the analysis bounds to [0, B].
// B is found, not guessed: the copy is built in a scratch module with the
// inputs as arguments and tried at powers of two between 2^8 and 2^31 (a
// binary search over the exponent, one try per bit of the span, since a
// smaller bound fits whatever a larger one does), the analysis run on it
// each time, and the largest B kept at which
// every elementwise integer op in it wider than 32 bits, but an
// accumulation, fits. Interval arithmetic over the body is what the
// analysis computes, so the body's own arithmetic decides the bound. The
// narrowing then runs on that copy under the analysis of the chosen B, and
// leaves wide an op whose 32-bit form would compute something else (a
// shift by 32 or more, a signed remainder that may see INT32_MIN % -1, an
// op that reads a negative word unsigned) and an accumulation, whose range
// no bound narrows; the copy is cloned into the version, and the function
// itself is never analysed.

#include "idr/Support/Actions.h"
#include "idr/Transforms/Narrow.h"

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Remarks.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"

#include <bit>

namespace idr {
#define GEN_PASS_DEF_IDRNARROWLANES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::narrow {

namespace {

// idr-narrow-lanes gives one vectorized loop its 32-bit version; the unit
// is the scf.for.
struct NarrowLanesVersionAction : support::TaggedAction<NarrowLanesVersionAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-narrow-lanes-version";
};

// The exponents of the bounds tried: below 2^31 every index fits i32, and
// below 2^8 a version runs on too few elements to matter. The search tries
// each bit of the span between them once, the largest first.
constexpr unsigned minExponent = 8;
constexpr unsigned maxExponent = 31;
constexpr auto spanBits = static_cast<unsigned>(std::bit_width(maxExponent - minExponent));

// A remark of the category idr-narrow-lanes at `loc`, when the context's
// remark engine has it on, written as the engine writes a remark it
// prints. It goes out through the diagnostic engine: the pass runs on the
// pass manager's workers, whose diagnostics the manager holds per function
// and emits in the functions' order on its own thread once they are done.
// The remark engine reports to one policy and one streamer that no lock
// guards, so the pass only reads its filter, which nothing writes after
// the context is set up.
template <typename Kind>
void remarkAt(Location loc, StringRef name, const Twine &text) {
  constexpr StringRef category = "idr-narrow-lanes";
  remark::detail::RemarkEngine *engine = loc->getContext()->getRemarkEngine();
  Kind made(loc, remark::RemarkOpts::name(name).category(category));
  if (!engine || !engine->isRemarkEnabled(made.getRemarkKind(), category))
    return;
  made << StringRef(text.str());
  emitRemark(loc, made.getMsg());
}

// What the pass did with the vectorized loops that compute on wide lanes:
// the loops versioned with 32-bit lanes, and the ones left wide.
struct LaneCounts {
  uint64_t narrowed = 0;
  uint64_t wide = 0;
};

// Whether `loop` is an outermost vectorized loop on wide integer lanes: a
// loop inside a vectorized one is part of it, and is left to it.
bool outermostOnWideLanes(scf::ForOp loop) {
  if (!isVectorized(loop) || !computesWideLanes(loop))
    return false;
  for (auto outer = loop->getParentOfType<scf::ForOp>(); outer;
       outer = outer->getParentOfType<scf::ForOp>())
    if (isVectorized(outer))
      return false;
  return true;
}

// A bound under which the copy's integer ops fit, 2^exponent, and the
// analysis of the copy under it.
struct Fitting {
  unsigned exponent;
  std::unique_ptr<DataFlowSolver> solver;
};

// The largest bound under which the copy's integer ops fit, with its
// analysis, the copy set to it; none when they fit under none, failure
// when an analysis fails. A smaller bound fits whatever a larger one does,
// so the search tries the least exponent, then adds each bit of the span,
// the largest first, that keeps the copy fitting.
FailureOr<std::optional<Fitting>> largestFitting(Copy &copy) {
  std::optional<Fitting> best;
  auto tryAt = [&](unsigned exponent) -> LogicalResult {
    FailureOr<std::unique_ptr<DataFlowSolver>> solver = copy.analyse(exponent);
    if (failed(solver))
      return failure();
    if (copy.fits(**solver))
      best = Fitting{exponent, std::move(*solver)};
    return success();
  };
  if (failed(tryAt(minExponent)))
    return failure();
  if (!best)
    return std::optional<Fitting>();
  for (unsigned bit : llvm::reverse(llvm::seq(0u, spanBits))) {
    unsigned candidate = best->exponent + (1u << bit);
    if (candidate > maxExponent)
      continue;
    if (failed(tryAt(candidate)))
      return failure();
  }
  // The copy holds the bound tried last; the analysis kept is the best's.
  copy.bound(best->exponent);
  return best;
}

// `loop` versioned with 32-bit lanes under a bound on its sizes, or left as
// it is with a remark, or without one, counted neither narrowed nor wide,
// when an action handler skips its version; failure, reported at the loop,
// when an analysis of its copy fails, an internal error.
LogicalResult versionLanes(RewriterBase &rewriter, scf::ForOp loop, LaneCounts &counts) {
  Location loc = loop.getLoc();
  auto wide = [&](const Twine &why) {
    remarkAt<remark::detail::OptRemarkMissed>(loc, "Wide", "the lanes stay 64-bit: " + why);
    ++counts.wide;
    return success();
  };
  if (runsAtMostOnce(loop))
    return wide("the loop runs at most once, which no version pays for");
  SetVector<Value> inputs = inputsOf(loop);
  if (llvm::none_of(inputs, testable))
    return wide("the loop reads no size from outside");
  // The scratch module goes with `copy` on every path out of here.
  Copy copy = Copy::of(loc, loop, inputs);
  FailureOr<std::optional<Fitting>> fitting = largestFitting(copy);
  if (failed(fitting))
    return emitError(loc) << "internal error: idr-narrow-lanes: the analysis of a copy failed";
  if (!*fitting)
    return wide("its integer ops do not all fit 32 bits under any bound on the sizes");
  unsigned low = (*fitting)->exponent;
  copy.narrow(*(*fitting)->solver);

  // if (every tested input <= 2^low) { the copy } else { the loop }: one
  // test of each, one bound of each type, and some input is tested.
  if (!support::perform<NarrowLanesVersionAction>(loop, [&] {
        rewriter.setInsertionPoint(loop);
        llvm::MapVector<Type, Value> bounds;
        SmallVector<Value> tests;
        for (Value input : inputs) {
          if (!testable(input))
            continue;
          Value &bound = bounds[input.getType()];
          if (!bound)
            bound = arith::ConstantOp::create(
                rewriter, loc, IntegerAttr::get(input.getType(), int64_t{1} << low));
          tests.push_back(
              arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ule, input, bound));
        }
        Value guard = tests.front();
        for (Value test : llvm::drop_begin(tests))
          guard = arith::AndIOp::create(rewriter, loc, guard, test);
        auto branch =
            scf::IfOp::create(rewriter, loc, TypeRange{}, guard, /*withElseRegion=*/true);
        rewriter.setInsertionPointToStart(branch.thenBlock());
        copy.cloneInto(rewriter);
        // The loop as it was is a copy too; the loop, which has no results,
        // goes.
        rewriter.setInsertionPoint(branch.elseBlock()->getTerminator());
        rewriter.clone(*loop);
        rewriter.eraseOp(loop);
      }))
    return success();
  remarkAt<remark::detail::OptRemarkPass>(
      loc, "Narrowed", "the integer lanes compute in 32 bits for sizes up to 2^" + Twine(low));
  ++counts.narrowed;
  return success();
}

struct NarrowLanes : idr::impl::IdrNarrowLanesBase<NarrowLanes> {
  using IdrNarrowLanesBase::IdrNarrowLanesBase;

  void runOnOperation() override {
    // The loops are found first, inner ones first, and versioned after:
    // each is outermost, so none holds another, and a version's copies
    // are no loops of the list.
    SmallVector<scf::ForOp> loops;
    getOperation()->walk([&](scf::ForOp loop) {
      if (outermostOnWideLanes(loop))
        loops.push_back(loop);
    });
    LaneCounts counts;
    IRRewriter rewriter(&getContext());
    for (scf::ForOp loop : loops)
      if (failed(versionLanes(rewriter, loop, counts)))
        return signalPassFailure();
    numNarrowed += counts.narrowed;
    numWide += counts.wide;
    if (counts.narrowed == 0)
      markAllAnalysesPreserved();
  }
};

} // namespace

} // namespace idr::narrow
