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
// every elementwise integer op in it wider than 32 bits fits, and is one
// whose 32-bit form computes what it computes (`exact`). Interval
// arithmetic over the body is what the analysis computes, so the body's
// own arithmetic decides the bound. The narrowing then runs on that copy
// under the analysis of the chosen B, and the copy is cloned into the
// version; the function itself is never analysed.

#include "idr/Idr.h"

#include "mlir/Analysis/DataFlow/IntegerRangeAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/Arith/Transforms/Passes.h"
#include "mlir/Dialect/Vector/IR/VectorOps.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/Remarks.h"
#include "mlir/Interfaces/CastInterfaces.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "mlir/Transforms/RegionUtils.h"

#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;
using namespace mlir::dataflow;

namespace idr {
#define GEN_PASS_DEF_IDRNARROWLANES
#include "idr/Passes.h.inc"
} // namespace idr

import idr.graph;

namespace {

// The exponents of the bounds tried: below 2^31 every index fits i32, and
// below 2^8 a version runs on too few elements to matter.
constexpr unsigned minExponent = 8;
constexpr unsigned maxExponent = 31;

// Whether `loop` is vectorized, as its ops say: it computes on vectors, has
// no results (a loop over buffers), and holds nothing but vector ops, the
// loops of its tiles and ops with neither effects nor regions. A tile the
// vectorizer refused keeps its linalg.generic, and a branch or a call
// keeps its scalar code, so a loop holding one is not vectorized, nor is a
// loop around a vectorized one that stores: the tile loops are the
// outermost such loops.
bool isVectorized(scf::ForOp loop) {
  if (loop->getNumResults() != 0)
    return false;
  bool vectors = false;
  WalkResult walk = loop.walk([&](Operation *op) {
    if (isa_and_nonnull<vector::VectorDialect>(op->getDialect())) {
      vectors = true;
      return WalkResult::advance();
    }
    if (isa<scf::ForOp, scf::YieldOp>(op))
      return WalkResult::advance();
    if (op->getNumRegions() != 0 || !isMemoryEffectFree(op))
      return WalkResult::interrupt();
    return WalkResult::advance();
  });
  return vectors && !walk.wasInterrupted();
}

// The values `loop` reads from outside it, in the order of their first use.
SetVector<Value> inputsOf(scf::ForOp loop) {
  SetVector<Value> inputs;
  inputs.insert_range(loop->getOperands());
  getUsedValuesDefinedAbove(loop->getRegions(), inputs);
  return inputs;
}

// Whether `value` is one the version tests: an integer wider than 32 bits
// or an index, no constant, whose range the analysis cannot know.
bool testable(Value value) {
  Type type = value.getType();
  return (type.isIndex() || (type.isSignlessInteger() && type.getIntOrFloatBitWidth() > 32)) &&
         !matchPattern(value, m_Constant());
}

// Whether a word of `range` fits a signed 32-bit one.
bool fits32(const ConstantIntRanges &range) {
  return range.smin().getSignificantBits() <= 32 && range.smax().getSignificantBits() <= 32;
}

// The range `solver` gives `value`; none where it gives none, as in code
// the analysis never reached.
std::optional<ConstantIntRanges> rangeOf(DataFlowSolver &solver, Value value) {
  auto *state = solver.lookupState<IntegerValueRangeLattice>(value);
  if (!state || state->getValue().isUninitialized())
    return std::nullopt;
  return state->getValue().getValue();
}

// Whether `range` holds the 32-bit word `word`, read signed.
bool holds(const ConstantIntRanges &range, const APInt &word) {
  APInt wide = word.sext(range.smin().getBitWidth());
  return range.smin().sle(wide) && range.smax().sge(wide);
}

// PIN(int-range-narrowing-exactness): whether the 32-bit form of `op`,
// whose operands and results fit a signed 32-bit word, computes what `op`
// computes. The arith ops are the ones whose 32-bit forms are known, and
// for three of them the fit is not enough, which is all upstream's
// narrowing asks: a shift by 32 or more is poison in 32 bits; INT32_MIN %
// -1 overflows there (the division traps) where it is 0 in 64; and an op
// that reads its operands unsigned reads a negative word as another number
// in each width, which a remainder sees.
bool exact(Operation *op, DataFlowSolver &solver) {
  if (!isa_and_nonnull<arith::ArithDialect>(op->getDialect()))
    return false;
  auto operand = [&](unsigned i) { return rangeOf(solver, op->getOperand(i)); };
  if (isa<arith::ShLIOp, arith::ShRSIOp, arith::ShRUIOp>(op)) {
    std::optional<ConstantIntRanges> amount = operand(1);
    if (!amount || amount->umax().uge(32))
      return false;
  }
  if (isa<arith::RemSIOp>(op)) {
    std::optional<ConstantIntRanges> dividend = operand(0), divisor = operand(1);
    if (!dividend || !divisor ||
        (holds(*dividend, APInt::getSignedMinValue(32)) && holds(*divisor, APInt::getAllOnes(32))))
      return false;
  }
  if (isa<arith::DivUIOp, arith::CeilDivUIOp, arith::RemUIOp, arith::ShRUIOp, arith::MaxUIOp,
          arith::MinUIOp>(op))
    return llvm::all_of(op->getOperands(), [&](Value value) {
      std::optional<ConstantIntRanges> range = rangeOf(solver, value);
      return range && range->smin().isNonNegative();
    });
  return true;
}

// What `op` computes on: whether on integers wider than 32 bits (an
// elementwise op that is no cast, with such an operand or result), and
// whether on lanes of them.
struct Width {
  bool wide = false;
  bool lanes = false;
};
Width widthOf(Operation *op) {
  Width width;
  if (!op->hasTrait<OpTrait::Elementwise>() || isa<CastOpInterface>(op))
    return width;
  auto note = [&](Type type) {
    if (ConstantIntRanges::getStorageBitwidth(type) <= 32)
      return;
    width.wide = true;
    width.lanes |= isa<VectorType>(type);
  };
  for (Type type : op->getOperandTypes())
    note(type);
  for (Type type : op->getResultTypes())
    note(type);
  return width;
}

// Whether `loop` computes on lanes of integers wider than 32 bits, which is
// what the narrowing is for.
bool computesWideLanes(scf::ForOp loop) {
  return loop
      .walk([](Operation *op) { return widthOf(op).lanes ? WalkResult::interrupt() : WalkResult::advance(); })
      .wasInterrupted();
}

// The copy of a loop in a scratch module: a function of the values the
// loop reads from outside, each testable one behind arith.minui of itself
// and the bound, a constant the trials set.
class Copy {
public:
  Copy(Location loc, scf::ForOp loop, const SetVector<Value> &inputs) : module(ModuleOp::create(loc)) {
    MLIRContext *ctx = loc.getContext();
    SmallVector<Type> argTypes;
    for (Value input : inputs)
      if (!matchPattern(input, m_Constant()))
        argTypes.push_back(input.getType());
    function = func::FuncOp::create(loc, "copy", FunctionType::get(ctx, argTypes, {}));
    module.push_back(function);
    Block *entry = function.addEntryBlock();
    OpBuilder b = OpBuilder::atBlockEnd(entry);
    IRMapping into;
    unsigned next = 0;
    for (Value input : inputs) {
      if (matchPattern(input, m_Constant())) {
        into.map(input, b.clone(*input.getDefiningOp())->getResult(0));
        continue;
      }
      Value arg = entry->getArgument(next++);
      if (testable(input)) {
        Value &bound = bounds[input.getType()];
        if (!bound)
          bound = arith::ConstantOp::create(b, loc, IntegerAttr::get(input.getType(), 0));
        arg = arith::MinUIOp::create(b, loc, arg, bound);
      }
      into.map(input, arg);
    }
    copy = b.clone(*loop, into);
    func::ReturnOp::create(b, loc);
  }
  ~Copy() { module.erase(); }
  Copy(const Copy &) = delete;
  Copy &operator=(const Copy &) = delete;

  // The analysis of the copy with the bound 2^exponent; none when the
  // solver fails, which is an internal error.
  std::unique_ptr<DataFlowSolver> analyse(unsigned exponent) {
    for (auto [type, bound] : bounds)
      cast<arith::ConstantOp>(bound.getDefiningOp())
          .setValueAttr(IntegerAttr::get(type, int64_t{1} << exponent));
    auto solver = std::make_unique<DataFlowSolver>(DataFlowConfig().setInterprocedural(false));
    loadBaselineAnalyses(*solver);
    solver->load<IntegerRangeAnalysis>();
    if (failed(solver->initializeAndRun(module)))
      return nullptr;
    return solver;
  }

  // Whether, under `solver`'s analysis, every op of the copied loop that
  // computes on integers wider than 32 bits fits 32 bits and computes the
  // same there (the stand-ins before it read the inputs, which fit nothing).
  bool fits(DataFlowSolver &solver) {
    auto fit = [&](Value value) {
      if (ConstantIntRanges::getStorageBitwidth(value.getType()) == 0)
        return true;
      std::optional<ConstantIntRanges> range = rangeOf(solver, value);
      return range && fits32(*range);
    };
    return !copy
                ->walk([&](Operation *op) {
                  if (!widthOf(op).wide ||
                      (llvm::all_of(op->getOperands(), fit) && llvm::all_of(op->getResults(), fit) &&
                       exact(op, solver)))
                    return WalkResult::advance();
                  return WalkResult::interrupt();
                })
                .wasInterrupted();
  }

  // Narrows the copy under `solver`'s analysis: upstream's patterns, in
  // upstream's order (bottom-up, so that a comparison still finds the
  // ranges of its operands), the solver told of the ops they erase. No
  // folding and no region simplification, as in upstream's own
  // int-range-optimizations: those can erase a block argument without a
  // word to the solver, and a new one at its address would take its range.
  // Failure when the patterns do not converge.
  LogicalResult narrow(DataFlowSolver &solver) {
    struct Listener : RewriterBase::Listener {
      explicit Listener(DataFlowSolver &s) : solver(s) {}
      void notifyOperationErased(Operation *op) override {
        solver.eraseState(solver.getProgramPointAfter(op));
        for (Value result : op->getResults())
          solver.eraseState(result);
      }
      DataFlowSolver &solver;
    } listener(solver);
    RewritePatternSet patterns(module.getContext());
    arith::populateIntRangeNarrowingPatterns(patterns, solver, {32});
    if (failed(applyPatternsGreedily(function.getBody(), FrozenRewritePatternSet(std::move(patterns)),
                                     GreedyRewriteConfig()
                                         .setUseTopDownTraversal(false)
                                         .enableFolding(false)
                                         .setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled)
                                         .setListener(&listener))))
      return failure();
    // The narrowing widens a result back with arith.extui, and knows the
    // word it widens is non-negative (its range, kept on the cast); the
    // flag says so where LLVM reads it, so that the conversion to double
    // of such a word is the signed one (uitofp nneg, after the
    // canonicalization of sitofp of it), which the target has for 32-bit
    // lanes where it has no unsigned one.
    function.walk([&](arith::ExtUIOp widen) {
      std::optional<ConstantIntRanges> range = rangeOf(solver, widen.getResult());
      if (range && range->smin().isNonNegative() && fits32(*range))
        widen.setNonNeg(true);
    });
    return success();
  }

  // Clones the copy's body at `b`, its arguments standing for `inputs`
  // again.
  void cloneInto(OpBuilder &b, const SetVector<Value> &inputs) {
    Block &entry = function.getBody().front();
    IRMapping back;
    unsigned next = 0;
    for (Value input : inputs)
      if (!matchPattern(input, m_Constant()))
        back.map(entry.getArgument(next++), input);
    for (Operation &op : entry.without_terminator())
      b.clone(op, back);
  }

private:
  ModuleOp module;
  func::FuncOp function;
  // The copied loop, after the stand-ins.
  Operation *copy = nullptr;
  // The bound: one constant per type of input tested.
  llvm::MapVector<Type, Value> bounds;
};

struct NarrowLanes : idr::impl::IdrNarrowLanesBase<NarrowLanes> {
  using IdrNarrowLanesBase::IdrNarrowLanesBase;

  void runOnOperation() override {
    // The outermost vectorized loops: a loop inside one is part of it.
    SmallVector<scf::ForOp> loops;
    getOperation().walk<WalkOrder::PreOrder>([&](scf::ForOp loop) {
      if (!isVectorized(loop))
        return WalkResult::advance();
      loops.push_back(loop);
      return WalkResult::skip();
    });
    IRRewriter rewriter(&getContext());
    for (scf::ForOp loop : loops)
      if (computesWideLanes(loop) && failed(version(rewriter, loop)))
        return signalPassFailure();
  }

  LogicalResult version(IRRewriter &rewriter, scf::ForOp loop) {
    Location loc = loop.getLoc();
    auto wide = [&](const Twine &why) {
      remark::missed(loc, remark::RemarkOpts::name("Wide").category("idr-narrow-lanes"))
          << ("the lanes stay 64-bit: " + why).str();
      ++numWide;
      return success();
    };
    auto internal = [&](const Twine &what) -> LogicalResult {
      return emitError(loc) << "internal error: idr-narrow-lanes: " << what;
    };
    if (idr::graph::runsAtMostOnce(loop))
      return wide("the loop runs at most once, which no version pays for");
    SetVector<Value> inputs = inputsOf(loop);
    if (llvm::none_of(inputs, testable))
      return wide("the loop reads no size from outside");
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
      return wide("its integer ops do not all compute the same in 32 bits under any bound on the sizes");
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
    rewriter.moveOpBefore(loop, branch.elseBlock()->getTerminator());
    remark::passed(loc, remark::RemarkOpts::name("Narrowed").category("idr-narrow-lanes"))
        << ("the integer lanes compute in 32 bits for sizes up to 2^" + Twine(low)).str();
    ++numNarrowed;
    return success();
  }
};

} // namespace
