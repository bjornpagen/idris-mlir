// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The values that flow around loops and out of merges made words where
// every value that may flow there fits: the webs the joints carry, decided
// on the facts' numbers, and each joint's part of the rewrite as the walk
// enters and leaves it.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Generated/Actions.h.inc"
#include "idr/Support/Actions.h"
#include "idr/Support/Match.h"
#include "idr/Transforms/Narrow.h"

#include "mlir/IR/PatternMatch.h"

#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::narrow {

namespace {

// idr-narrow makes one web's carried bigs words; the unit is the joint at
// which the walk first meets the web.
struct NarrowJointAction : support::TaggedAction<NarrowJointAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::narrowJoint;
};

// Retypes the big result `result` to i64: its uses get the small of it.
void narrowResult(WordRewriter &rewriter, OpResult result) {
  Type type = result.getType();
  rewriter.modifyOpInPlace(result.getOwner(), [&] { result.setType(rewriter.getI64Type()); });
  rewriter.setInsertionPointAfter(result.getOwner());
  Value made = rewriter.standIn(result.getLoc(), type, result);
  rewriter.replaceAllUsesExcept(result, made, made.getDefiningOp());
}

// Passes the word of `operand` instead of the big. The operands narrowed
// here are forwarded where they are passed (a loop's start, a yield), which
// moves a counted big's reference on, so the big gives it up there:
// counting ran before, and the word takes nothing. A small holds no
// reference, so the rule moves none on, and passing its word gives nothing
// up; one given as the big the forwarding asked goes with the use.
void passWord(RewriterBase &rewriter, OpOperand &operand) {
  Operation *owner = operand.getOwner();
  Location loc = owner->getLoc();
  rewriter.setInsertionPoint(owner);
  Value value = operand.get();
  Replaced big = replace(rewriter, loc, operand);
  Value made = word(rewriter, loc, big.read);
  giveUp(rewriter, loc, big);
  rewriter.modifyOpInPlace(owner, [&] { operand.set(made); });
  eraseGiven(rewriter, value);
}

bool carries(const Facts &facts, const Decisions &decided, const Carry &carry) {
  return decided.carried.test(facts.inputs(carry).front());
}

// Whether `pass` forwards what a call in tail position gives: its word,
// passed instead, would be made after the call, which then could not
// leave its frame, so no web holding it is carried.
bool givenByTailCall(const Facts &facts, const Pass &pass) {
  Operation *source = throughLinear(facts.value(pass.from)).getDefiningOp();
  return source && isa<TailCallOp>(source);
}

} // namespace

void narrowArgument(WordRewriter &rewriter, BlockArgument arg) {
  Type type = arg.getType();
  rewriter.modifyOpInPlace(arg.getOwner()->getParentOp(),
                           [&] { arg.setType(rewriter.getI64Type()); });
  rewriter.setInsertionPointToStart(arg.getOwner());
  Value made = rewriter.standIn(arg.getLoc(), type, arg);
  rewriter.replaceAllUsesExcept(arg, made, made.getDefiningOp());
}

// A web is carried when every value it becomes and every value forwarded
// into it fits, and nothing forwarded into it is what a tail call gives.
// The joints are met in the walk's order, so each web's action is taken at
// the first joint whose class it is, after everything inside that joint;
// whether any web is carried.
Changed decideJoints(const Facts &facts, Decisions &decided) {
  BitSet<ValueId> unfit(facts.count()), met(facts.count()), webs(facts.count());
  auto eachCarry = [&](auto &&each) {
    for (const Step &step : facts.steps())
      match(
          step, [](const Enter &) {}, [](const Word &) {},
          [&](const Leave &leave) {
            for (const Carry &carry : facts.carries(leave.carries, leave.carriesEnd))
              each(leave, carry);
          });
  };
  auto fit = [&](ValueId v) { return facts.fits(v); };
  eachCarry([&](const Leave &, const Carry &carry) {
    if (!llvm::all_of(facts.inputs(carry), fit) ||
        !llvm::all_of(facts.passes(carry), [&](const Pass &pass) {
          return fit(pass.from) && !givenByTailCall(facts, pass);
        }))
      (void)unfit.raise(facts.web(facts.inputs(carry).front()));
  });
  Changed carried = Changed::No;
  eachCarry([&](const Leave &leave, const Carry &carry) {
    ValueId web = facts.web(facts.inputs(carry).front());
    if (unfit.test(web) || met.raise(web) == Changed::No)
      return;
    if (support::perform<NarrowJointAction>(leave.joint, [&] { (void)webs.raise(web); }))
      carried = Changed::Yes;
  });
  eachCarry([&](const Leave &, const Carry &carry) {
    if (!webs.test(facts.web(facts.inputs(carry).front())))
      return;
    for (ValueId v : facts.inputs(carry))
      (void)decided.carried.raise(v);
    for (const Pass &pass : facts.passes(carry))
      (void)decided.asked.raise(pass.from);
  });
  return carried;
}

// Entering a joint, each argument of its regions that a web carries
// becomes a word, so that what runs inside reads the small of the word.
void enter(WordRewriter &rewriter, const Facts &facts, const Decisions &decided,
           const Enter &step) {
  for (ValueId v : facts.ownOf(step))
    if (decided.carried.test(v))
      narrowArgument(rewriter, cast<BlockArgument>(facts.value(v)));
}

// Leaving a joint, class by class, what it forwards into a carried web is
// passed as its word and each result the web holds becomes a word; then
// each carried result no class of its own holds. An argument a class holds
// is a region's, made a word as the walk entered its op, or an enclosing
// op's, made a word as the walk entered that op.
void leave(WordRewriter &rewriter, const Facts &facts, const Decisions &decided,
           const Leave &step) {
  auto own = [&](ValueId v) {
    auto result = dyn_cast<OpResult>(facts.value(v));
    return result && result.getOwner() == step.joint ? result : OpResult();
  };
  for (const Carry &carry : facts.carries(step.carries, step.carriesEnd)) {
    if (!carries(facts, decided, carry))
      continue;
    for (const Pass &pass : facts.passes(carry))
      passWord(rewriter, *pass.operand);
    for (ValueId v : facts.inputs(carry))
      if (OpResult result = own(v))
        narrowResult(rewriter, result);
  }
  for (ValueId v : facts.ownOf(step))
    if (decided.carried.test(v))
      narrowResult(rewriter, cast<OpResult>(facts.value(v)));
}

} // namespace idr::narrow
