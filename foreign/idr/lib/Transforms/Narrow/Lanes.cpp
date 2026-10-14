// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-narrow-lanes: the integer lanes of a vectorized loop compute in 32
// bits under a runtime bound on its index space. A loop over an array
// computes its indices as the 64-bit Int the program wrote (idr-lower
// casts linalg.index to the word), and the target's lanes pay for it:
// neither x86-64-v3 nor NEON has a 64-bit vector multiply, and x86-64-v3
// has no int64-to-double conversion, so LLVM emulates the one and
// scalarizes the other, where 32-bit lanes have both. Each vectorized loop
// that computes on lanes of integers wider than 32 bits becomes two
// versions: where every integer it reads from outside (the sizes, the tile
// bound) is at most B, a copy in which every integer op that integer range
// analysis proves fits 32 bits is narrowed by upstream's
// arith-int-range-narrowing; otherwise the loop as it was. A loop that
// runs at most once, as upstream's value bounds see its bounds (the loop
// of a peeled tile loop's last tile), stays as it is: its version would
// never pay for the code it adds.
//
// The bound is an SSA fact, since the analysis reads no branch condition:
// in the copy each such input stands behind arith.minui of itself and B,
// which equals it under the guard and which the analysis bounds to [0, B].
// B is found, not guessed: the copy is built in a scratch module with the
// inputs as arguments and tried at powers of two from 2^31 down (a binary
// search over the exponent: a smaller bound fits whatever a larger one
// does), the analysis run on it each time, and the largest B kept at which
// every elementwise integer op in it wider than 32 bits fits. Interval
// arithmetic over the body is what the analysis computes, so the body's
// own arithmetic decides the bound. The narrowing then runs on that copy
// under the analysis of the chosen B, and leaves wide an op whose 32-bit
// form would compute something else (a shift by 32 or more, a signed
// remainder that may see INT32_MIN % -1, an op that reads a negative word
// unsigned); the copy is cloned into the version, and the function itself
// is never analysed.

#include "idr/Transforms/Narrow.h"

#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/Remarks.h"
#include "mlir/Transforms/WalkPatternRewriteDriver.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Twine.h"

namespace idr {
#define GEN_PASS_DEF_IDRNARROWLANES
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::narrow {

namespace {

// The exponents of the bounds tried: below 2^31 every index fits i32, and
// below 2^8 a version runs on too few elements to matter.
constexpr unsigned minExponent = 8;
constexpr unsigned maxExponent = 31;

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
// the loops versioned with 32-bit lanes, the ones left wide, and whether an
// internal error stopped one.
struct LaneCounts {
  uint64_t narrowed = 0;
  uint64_t wide = 0;
  bool failed = false;
};

// An outermost vectorized loop on wide integer lanes, versioned with 32-bit
// lanes under a bound on its sizes, or left as it is with a remark. The
// walk reaches inner loops first; a loop inside a vectorized one is part of
// it, and is left to it.
struct VersionLanes : OpRewritePattern<scf::ForOp> {
  VersionLanes(MLIRContext *ctx, LaneCounts &counts) : OpRewritePattern(ctx), counts(counts) {}

  LogicalResult matchAndRewrite(scf::ForOp loop, PatternRewriter &rewriter) const override {
    if (!isVectorized(loop) || !computesWideLanes(loop))
      return failure();
    for (auto outer = loop->getParentOfType<scf::ForOp>(); outer;
         outer = outer->getParentOfType<scf::ForOp>())
      if (isVectorized(outer))
        return failure();

    Location loc = loop.getLoc();
    auto wide = [&](const Twine &why) {
      remarkAt<remark::detail::OptRemarkMissed>(loc, "Wide", "the lanes stay 64-bit: " + why);
      ++counts.wide;
      return failure();
    };
    auto internal = [&](const Twine &what) {
      emitError(loc) << "internal error: idr-narrow-lanes: " << what;
      counts.failed = true;
      return failure();
    };
    if (runsAtMostOnce(loop))
      return wide("the loop runs at most once, which no version pays for");
    SetVector<Value> inputs = inputsOf(loop);
    if (llvm::none_of(inputs, testable))
      return wide("the loop reads no size from outside");
    // The scratch module goes with `copy` on every path out of here.
    Copy copy(loc, loop, inputs);
    // Whether the copy's integer ops fit under the bound 2^exponent.
    auto fitsAt = [&](unsigned exponent) -> FailureOr<bool> {
      std::unique_ptr<DataFlowSolver> solver = copy.analyse(exponent);
      if (!solver)
        return failure();
      return copy.fits(*solver);
    };
    FailureOr<bool> least = fitsAt(minExponent);
    if (failed(least))
      return internal("the analysis of a copy failed");
    if (!*least)
      return wide("its integer ops do not all fit 32 bits under any bound on the sizes");
    unsigned low = minExponent, high = maxExponent;
    while (low < high) {
      unsigned mid = (low + high + 1) / 2;
      FailureOr<bool> at = fitsAt(mid);
      if (failed(at))
        return internal("the analysis of a copy failed");
      if (*at)
        low = mid;
      else
        high = mid - 1;
    }
    std::unique_ptr<DataFlowSolver> solver = copy.analyse(low);
    if (!solver)
      return internal("the analysis of a copy failed");
    if (failed(copy.narrow(*solver)))
      return internal("the narrowing of a copy did not converge");

    // if (every tested input <= 2^low) { the copy } else { the loop }.
    rewriter.setInsertionPoint(loop);
    llvm::MapVector<Type, Value> bounds;
    Value guard;
    for (Value input : inputs) {
      if (!testable(input))
        continue;
      Value &bound = bounds[input.getType()];
      if (!bound)
        bound = arith::ConstantOp::create(rewriter, loc,
                                          IntegerAttr::get(input.getType(), int64_t{1} << low));
      Value test = arith::CmpIOp::create(rewriter, loc, arith::CmpIPredicate::ule, input, bound);
      guard = guard ? Value(arith::AndIOp::create(rewriter, loc, guard, test)) : test;
    }
    auto branch = scf::IfOp::create(rewriter, loc, TypeRange{}, guard, /*withElseRegion=*/true);
    rewriter.setInsertionPointToStart(branch.thenBlock());
    copy.cloneInto(rewriter, inputs);
    // The loop as it was is a copy too, which the walk does not visit; the
    // matched loop, which has no results, goes.
    rewriter.setInsertionPoint(branch.elseBlock()->getTerminator());
    rewriter.clone(*loop);
    rewriter.eraseOp(loop);
    remarkAt<remark::detail::OptRemarkPass>(
        loc, "Narrowed", "the integer lanes compute in 32 bits for sizes up to 2^" + Twine(low));
    ++counts.narrowed;
    return success();
  }

  LaneCounts &counts;
};

struct NarrowLanes : idr::impl::IdrNarrowLanesBase<NarrowLanes> {
  using IdrNarrowLanesBase::IdrNarrowLanesBase;

  void runOnOperation() override {
    LaneCounts counts;
    RewritePatternSet patterns(&getContext());
    patterns.add<VersionLanes>(&getContext(), counts);
    walkAndApplyPatterns(getOperation(), std::move(patterns));
    // The pattern reported the error at its loop.
    if (counts.failed)
      return signalPassFailure();
    numNarrowed += counts.narrowed;
    numWide += counts.wide;
    if (counts.narrowed == 0)
      markAllAnalysesPreserved();
  }
};

} // namespace

} // namespace idr::narrow
