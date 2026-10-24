// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A loop whose natural only descends, versioned so that its copy proves the
// natural small.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Narrow.h"

#include "llvm/ADT/SetVector.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::narrow {

namespace {

// idr-narrow versions one loop on its descending natural; the unit is the
// scf.while.
struct NarrowVersionAction : support::TaggedAction<NarrowVersionAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::narrowVersion;
};

// Whether `yielded`, what `loop` yields round for its argument `arg`, is
// `arg` or a predecessor of it within one trip round the loop: through
// predecessors, the condition's forwarding, and every region of a merge.
// Each goal is a value and what decides on its path whether the loop goes
// round again, none in the region after the condition, which always does:
// a path on which that is false leaves the loop, and what it yields never
// comes back. Every goal must hold. Each step goes to a value defined
// before the one it starts from (an operand, what the condition forwards
// from the region before it, what a region of the merge yields), so no
// goal waits on itself; the goals are pairs of the loop's values, each
// asked once, so the asking ends.
bool descends(Value yielded, BlockArgument arg, scf::WhileOp loop) {
  using Goal = std::pair<Value, std::optional<Value>>;
  scf::ConditionOp condition = loop.getConditionOp();
  // Each goal enters once, and is read from the front.
  llvm::SetVector<Goal> goals;
  goals.insert({yielded, std::nullopt});
  for (size_t at = 0; at < goals.size(); ++at) {
    auto [value, again] = goals[at];
    if (value == arg)
      continue;
    APInt goes;
    if (again && matchPattern(*again, m_ConstantInt(&goes)) && goes.isZero())
      continue;
    if (auto pred = value.getDefiningOp<NatPredOp>()) {
      goals.insert({pred.getValue(), again});
      continue;
    }
    // A cast into or out of a linear position gives the same natural.
    if (Value moved = throughLinear(value); moved != value) {
      goals.insert({moved, again});
      continue;
    }
    if (auto forwarded = dyn_cast<BlockArgument>(value)) {
      if (forwarded.getOwner() != &loop.getAfter().front())
        return false;
      goals.insert(
          {condition.getArgs()[forwarded.getArgNumber()], Value(condition.getCondition())});
      continue;
    }
    auto result = cast<OpResult>(value);
    Operation *merge = result.getOwner();
    if (merge->getNumRegions() == 0 || !isa<RegionBranchOpInterface>(merge))
      return false;
    // A merge that gives the decision with the value decides in each region.
    auto decided = again ? dyn_cast<OpResult>(*again) : OpResult();
    bool together = decided && decided.getOwner() == merge;
    for (Region &region : merge->getRegions()) {
      if (region.empty())
        continue;
      Operation *terminator = region.front().getTerminator();
      // A region that ends the program yields nothing.
      if (terminator->getNumOperands() != merge->getNumResults()) {
        if (isa<RegionBranchTerminatorOpInterface>(terminator))
          return false;
        continue;
      }
      std::optional<Value> decision =
          together ? std::optional<Value>(terminator->getOperand(decided.getResultNumber())) : again;
      goals.insert({terminator->getOperand(result.getResultNumber()), decision});
    }
  }
  return true;
}

// The first natural argument of `loop` that only descends and that its
// bounds do not already prove small, or none.
std::optional<unsigned> descendingArgument(scf::WhileOp loop, const Bounded &bounded) {
  // A slot that carries a borrowed value passes it out of the loop
  // borrowed, which a branch between two copies of the loop would have to
  // take owned: such a loop stays one loop.
  if (llvm::any_of(loop.getInits(), borrowed))
    return std::nullopt;
  Block &before = loop.getBefore().front();
  auto yield = cast<scf::YieldOp>(loop.getAfter().front().getTerminator());
  for (BlockArgument arg : before.getArguments())
    if (isa<NatType>(unrestricted(arg.getType())) && !bounded.of(arg).fits() &&
        descends(yield.getOperand(arg.getArgNumber()), arg, loop))
      return arg.getArgNumber();
  return std::nullopt;
}

// if (init <= IDRIS_RT_SMALL_MAX) { the loop, from init masked to its low 62 bits }
// else { the loop }. On the first path the mask changes nothing, and shows
// the analysis the bound that a descending argument keeps. Both versions
// are copies, which the walk that versions does not visit, so a loop is
// versioned once. The natural is read where the loop took it: a natural
// used once leaves its linear position first, and the loop that still
// takes it gets it back in one.
void version(RewriterBase &rewriter, scf::WhileOp loop, unsigned index) {
  Location loc = loop.getLoc();
  MLIRContext *ctx = loop.getContext();
  Value init = loop.getInits()[index];
  Type nat = init.getType();
  rewriter.setInsertionPoint(loop);
  Replaced held = replace(rewriter, loc, loop.getInitsMutable()[index]);
  APInt max(64, static_cast<uint64_t>(IDRIS_RT_SMALL_MAX), /*isSigned=*/true);
  // The bound is static data, as a constant's type says; the natural is
  // read in place, so the comparison takes nothing of it.
  Value bound = ConstantOp::create(rewriter, loc, atHold(held.read.getType(), Hold::staticData()),
                                   BigAttr::get(ctx, max));
  Value fits = BigCmpOp::create(rewriter, loc, held.read, bound, CmpPredicate::lte);
  // The branch gives back the results something reads. A result nothing
  // reads is what the loop's condition forwards on the path not taken
  // (poison): left unread in each copy, it stays that, which the owned
  // stage's verifier sees, and passing it through the branch would not.
  SmallVector<unsigned> read;
  SmallVector<Type> types;
  for (OpResult result : loop->getResults())
    if (!result.use_empty()) {
      read.push_back(result.getResultNumber());
      types.push_back(result.getType());
    }
  auto resultsOf = [&](Operation *copy) {
    return llvm::map_to_vector(read, [&](unsigned at) { return Value(copy->getResult(at)); });
  };
  auto branch = scf::IfOp::create(rewriter, loc, types, fits, /*withElseRegion=*/true);
  // A branch that gives nothing back was built with its yields.
  auto yield = [&](ValueRange values) {
    if (!values.empty())
      scf::YieldOp::create(rewriter, loc, values);
  };

  rewriter.setInsertionPointToStart(branch.thenBlock());
  Value word = BigToIntOp::create(rewriter, loc, rewriter.getI64Type(), held.read);
  Value mask =
      arith::ConstantOp::create(rewriter, loc, rewriter.getI64IntegerAttr(IDRIS_RT_SMALL_MAX));
  Value masked = arith::AndIOp::create(rewriter, loc, word, mask);
  // A small, given as the natural the loop takes, which keeps the range
  // the mask proved.
  Value start = heldAs(rewriter, loc, small(rewriter, loc, nat, masked), nat);
  // The copy starts from the word, so the natural it was read from gives up
  // the reference the loop would have taken.
  giveUp(rewriter, loc, held);
  Operation *copy = rewriter.clone(*loop);
  rewriter.modifyOpInPlace(copy, [&] { copy->setOperand(index, start); });
  yield(resultsOf(copy));

  rewriter.setInsertionPointToStart(branch.elseBlock());
  Value back = heldAs(rewriter, loc, held.read, nat);
  Operation *otherwise = rewriter.clone(*loop);
  rewriter.modifyOpInPlace(otherwise, [&] { otherwise->setOperand(index, back); });
  yield(resultsOf(otherwise));
  for (auto [at, result] : llvm::zip_equal(read, branch.getResults()))
    rewriter.replaceAllUsesWith(loop->getResult(at), result);
  rewriter.eraseOp(loop);
}

struct VersionDescending : OpRewritePattern<scf::WhileOp> {
  VersionDescending(MLIRContext *ctx, const Bounded &bounded, uint64_t &versioned)
      : OpRewritePattern(ctx), bounded(bounded), versioned(versioned) {}

  LogicalResult matchAndRewrite(scf::WhileOp loop, PatternRewriter &rewriter) const override {
    std::optional<unsigned> index = descendingArgument(loop, bounded);
    if (!index)
      return failure();
    if (!support::perform<NarrowVersionAction>(loop,
                                               [&] { version(rewriter, loop, *index); }))
      return failure();
    ++versioned;
    return success();
  }

  const Bounded &bounded;
  uint64_t &versioned;
};

} // namespace

void populateVersionPatterns(RewritePatternSet &patterns, const Bounded &bounded,
                             uint64_t &versioned) {
  patterns.add<VersionDescending>(patterns.getContext(), bounded, versioned);
}

} // namespace idr::narrow
