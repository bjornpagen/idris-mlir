// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- WhileDo.cpp - The while-do loop of a body that is a decision -------===//
//
// A function whose body ends in a match with one region that calls itself
// and one that returns becomes the loop MLIR expects:
//   - the before region is the body up to the decision, and ends in
//     scf.condition(continue) over the arguments that change;
//   - the after region is the region that calls, its call's arguments
//     yielded as the next ones;
//   - the region that exits follows the loop, on the loop's results.
// Arguments the call passes unchanged are not carried at all, and code that
// depends on nothing the loop changes runs once, before it. A loop that
// counts up to a bound is then exactly what upstream's uplift recognizes,
// and becomes an scf.for with a trip count.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "mlir/Transforms/RegionUtils.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;

namespace idr::tail {
namespace {

class WhileDo {
public:
  WhileDo(FuncOp fn, Decision decision, RewriterBase &rewriter)
      : fn(fn), decision(decision), rewriter(rewriter) {}

  FailureOr<scf::WhileOp> build();

private:
  // Where code runs once the loop exists, and what it sees for the body's
  // values that pass through the loop, by slot (the carried arguments,
  // then what the body passes on): the before region with its arguments,
  // the after region with its, and the function's block after the loop
  // with the loop's results. The before region has only the carried
  // arguments, so what the body passes is itself there.
  struct Scope {
    Block *block;
    ValueRange values;
  };
  // The value `scope` sees for `value` of the body.
  Value in(Value value, const Scope &scope);
  // Every operand of `root` and of the ops nested in it, as `scope` sees it.
  void rescope(Operation *root, const Scope &scope);
  // The `i1` that holds when the decision takes the region that loops,
  // built at the end of the before block.
  Value continues();
  // Moves the ops of `region` to the end of `scope`'s block, its arguments
  // (a case's fields, or the scrutinee back) read from the scrutinee, and
  // returns its terminator.
  Operation *inlineRegion(Region &region, const Scope &scope);

  FuncOp fn;
  Decision decision;
  RewriterBase &rewriter;
  scf::WhileOp loop;
  Scope before, after, exit;
  // The arguments that change from one call to the next, by position.
  SmallVector<unsigned> carried;
  // What the body computes before the decision and the regions use: carried
  // by the loop after the arguments.
  SmallVector<Value> passed;
};

Value WhileDo::in(Value value, const Scope &scope) {
  Block &entry = fn.getBody().front();
  auto arg = dyn_cast<BlockArgument>(value);
  unsigned slot;
  if (arg && arg.getOwner() == &entry) {
    const auto *it = llvm::find(carried, arg.getArgNumber());
    if (it == carried.end())
      return value;
    slot = static_cast<unsigned>(it - carried.begin());
  } else {
    const auto *it = llvm::find(passed, value);
    if (it == passed.end())
      return value;
    slot = static_cast<unsigned>(carried.size()) + static_cast<unsigned>(it - passed.begin());
  }
  return slot < scope.values.size() ? scope.values[slot] : value;
}

void WhileDo::rescope(Operation *root, const Scope &scope) {
  SmallVector<Operation *> ops;
  root->walk([&](Operation *op) { ops.push_back(op); });
  for (Operation *op : ops)
    rewriter.modifyOpInPlace(op, [&] {
      for (OpOperand &operand : op->getOpOperands())
        operand.set(in(operand.get(), scope));
    });
}

Value WhileDo::continues() {
  MatchOpInterface match = decision.match;
  bool loopsFirst = &decision.loops == &match.getCaseRegion(0);
  Location loc = match->getLoc();
  rewriter.setInsertionPointToEnd(before.block);
  // `(x == k) == loopsFirst`: the first case is the case k, the other
  // region the default, or the second case.
  auto test = [&](Value x, IntegerAttr k) -> Value {
    auto predicate = loopsFirst ? arith::CmpIPredicate::eq : arith::CmpIPredicate::ne;
    // A test of a flag is the flag, or the comparison it holds, turned
    // around.
    if (auto extended = x.getDefiningOp<arith::ExtUIOp>();
        extended && extended.getIn().getType().isInteger(1) && k.getValue().ule(1)) {
      x = extended.getIn();
      k = rewriter.getIntegerAttr(x.getType(), k.getValue().trunc(1));
    }
    if (x.getType().isInteger(1)) {
      bool whenSet = (predicate == arith::CmpIPredicate::eq) == k.getValue().isOne();
      if (whenSet)
        return x;
      if (auto compare = x.getDefiningOp<arith::CmpIOp>())
        return arith::CmpIOp::create(rewriter, loc, arith::invertPredicate(compare.getPredicate()),
                                     compare.getLhs(), compare.getRhs());
    }
    Value key = arith::ConstantOp::create(rewriter, loc, k);
    return arith::CmpIOp::create(rewriter, loc, predicate, x, key);
  };
  Value scrutinee = in(match.getScrutinee(), before);
  // A literal's key, or a constructor's tag (its position in the
  // scrutinee's type): the two tests a match makes.
  if (auto lit = dyn_cast<MatchLitOp>(match.getOperation()))
    return test(scrutinee, cast<IntegerAttr>(lit.getCases()[0]));
  // The other region is the default, or the last case, which idr-lower
  // also takes for any constructor Idris proved impossible.
  auto sum = cast<MatchOp>(match.getOperation());
  return test(TagOp::create(rewriter, loc, scrutinee),
              rewriter.getI64IntegerAttr(static_cast<uint32_t>(sum.getCaseTag(0))));
}

Operation *WhileDo::inlineRegion(Region &region, const Scope &scope) {
  Block &from = region.front();
  Block *to = scope.block;
  // Uses of the body's values in the region see this scope's.
  for (Operation &op : from)
    rescope(&op, scope);
  // A case of a constructor binds its fields, read from the scrutinee, and
  // the default region has the scrutinee itself back. A field nothing reads
  // has no value.
  MatchOpInterface match = decision.match;
  std::optional<Tag> tag = match.knownTag(region);
  Value scrutinee = in(match.getScrutinee(), scope);
  SmallVector<Value> fields(from.getNumArguments());
  rewriter.setInsertionPointToEnd(to);
  for (BlockArgument field : from.getArguments()) {
    if (field.use_empty())
      continue;
    Value value = tag ? FieldOp::create(rewriter, field.getLoc(), scrutinee, *tag,
                                        field.getArgNumber())
                            .getResult()
                      : scrutinee;
    fields[field.getArgNumber()] = heldAs(rewriter, field.getLoc(), value, field.getType());
  }
  rewriter.inlineBlockBefore(&from, to, to->end(), fields);
  return to->getTerminator();
}

FailureOr<scf::WhileOp> WhileDo::build() {
  Block &entry = fn.getBody().front();
  Operation *match = decision.match;
  // An argument the call passes unchanged is not carried, unless the call
  // consumes a reference of it: then each iteration takes one, which the
  // yield to the next must consume as the call did.
  auto call = cast<CallOp>(decision.loops.front().getTerminator()->getPrevNode());
  for (BlockArgument arg : entry.getArguments()) {
    unsigned index = arg.getArgNumber();
    if (call.getArgs()[index] != arg || isOwned(arg.getType()))
      carried.push_back(index);
  }

  // The body before the decision: what depends only on arguments that do
  // not change, and holds no reference, runs once before the loop; the rest
  // runs in every iteration. This is how the before region is built, not
  // a motion out of a built loop: that is upstream's, after.
  SmallVector<Operation *> repeated;
  llvm::SmallPtrSet<Operation *, 16> outside;
  auto invariant = [&](Value value) {
    if (auto arg = dyn_cast<BlockArgument>(value))
      return arg.getOwner() == &entry && !llvm::is_contained(carried, arg.getArgNumber());
    return outside.contains(value.getDefiningOp());
  };
  for (Operation &op : llvm::make_range(entry.begin(), match->getIterator())) {
    bool once = op.getNumRegions() == 0 && isMemoryEffectFree(&op) && llvm::all_of(op.getOperands(), invariant) &&
                llvm::none_of(op.getResults(), [&](Value r) { return isOwned(r.getType()); });
    if (once)
      outside.insert(&op);
    else
      repeated.push_back(&op);
  }
  // What the regions use of the repeated part passes from the before
  // region to the rest as a plain value, one that holds no reference; the
  // scrutinee too, when a region reads it through its arguments (a case's
  // fields, the default's scrutinee back).
  llvm::SetVector<Value> needed;
  for (Region *region : {&decision.loops, &decision.exits})
    region->walk([&](Operation *op) {
      for (Value operand : op->getOperands())
        if (Operation *def = operand.getDefiningOp(); def && def->getBlock() == &entry && !outside.contains(def))
          needed.insert(operand);
    });
  Value scrutinee = decision.match.getScrutinee();
  auto readsArguments = [](Region *region) {
    return llvm::any_of(region->getArguments(), [](BlockArgument arg) { return !arg.use_empty(); });
  };
  if (Operation *def = scrutinee.getDefiningOp();
      def && !outside.contains(def) &&
      (readsArguments(&decision.loops) || readsArguments(&decision.exits)))
    needed.insert(scrutinee);
  if (llvm::any_of(needed, [&](Value value) { return isOwned(value.getType()); }))
    return failure();
  // The before region passes every argument it has on to the rest, as the
  // uplift expects. A world or linear argument that the decision's code
  // already takes, or that the decision itself takes apart, would then be
  // taken twice.
  auto takenBefore = [&](unsigned index) {
    BlockArgument arg = entry.getArgument(index);
    return quantityOf(arg.getType()) == Quantity::One && llvm::any_of(arg.getUsers(), [&](Operation *user) {
             Operation *top = entry.findAncestorOpInBlock(*user);
             return top && (top == match || top->isBeforeInBlock(match));
           });
  };
  if (llvm::any_of(carried, takenBefore))
    return failure();
  passed = needed.takeVector();

  Location loc = fn.getLoc();
  SmallVector<Type> types;
  SmallVector<Value> initValues;
  for (unsigned index : carried) {
    types.push_back(entry.getArgument(index).getType());
    initValues.push_back(entry.getArgument(index));
  }
  SmallVector<Type> through(types);
  for (Value value : passed)
    through.push_back(value.getType());
  rewriter.setInsertionPoint(match);
  loop = scf::WhileOp::create(rewriter, loc, through, initValues);
  SmallVector<Location> locs(through.size(), loc);
  Block *beforeBlock =
      rewriter.createBlock(&loop.getBefore(), {}, types, ArrayRef(locs).take_front(types.size()));
  Block *afterBlock = rewriter.createBlock(&loop.getAfter(), {}, through, locs);
  before = {beforeBlock, beforeBlock->getArguments()};
  after = {afterBlock, afterBlock->getArguments()};
  exit = {loop->getBlock(), loop->getResults()};
  for (Operation *op : repeated) {
    rewriter.moveOpBefore(op, beforeBlock, beforeBlock->end());
    rescope(op, before);
  }
  Value go = continues();
  SmallVector<Value> forwarded(loop.getBeforeArguments());
  llvm::append_range(forwarded, passed);
  scf::ConditionOp::create(rewriter, match->getLoc(), go, forwarded);

  // The region that loops: its call's arguments are the next iteration's.
  Operation *yield = inlineRegion(decision.loops, after);
  auto next = cast<CallOp>(yield->getPrevNode());
  rewriter.setInsertionPoint(yield);
  SmallVector<Value> values;
  for (unsigned index : carried)
    values.push_back(next.getArgs()[index]);
  scf::YieldOp::create(rewriter, yield->getLoc(), values);
  rewriter.eraseOp(yield);
  rewriter.eraseOp(next);
  if (!fn.getTotal()) {
    rewriter.setInsertionPointToStart(loop.getAfterBody());
    MayLoopOp::create(rewriter, loc);
  }

  // The region that exits runs after the loop; the function returns what
  // it yields. The region's ops go after the return, which then makes way
  // for them.
  Operation *ret = entry.getTerminator();
  Operation *exitEnd = inlineRegion(decision.exits, exit);
  rewriter.eraseOp(ret);
  rewriter.setInsertionPoint(exitEnd);
  if (auto result = dyn_cast<YieldOp>(exitEnd))
    ReturnOp::create(rewriter, result.getLoc(), result.getResults());
  else
    // A region that crashes: the function never returns there.
    ub::UnreachableOp::create(rewriter, exitEnd->getLoc());
  rewriter.eraseOp(exitEnd);
  rewriter.eraseOp(match);
  // What only the decision read (a flag widened for it, a comparison
  // turned around) is left over.
  eliminateTriviallyDeadOps(rewriter, loop.getBefore(), /*includeNestedRegions=*/false);
  return loop;
}

} // namespace

FailureOr<scf::WhileOp> whileDo(FuncOp fn, Decision decision, RewriterBase &rewriter) {
  return WhileDo(fn, decision, rewriter).build();
}

} // namespace idr::tail
