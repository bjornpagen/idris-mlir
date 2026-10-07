// idr.tail:whileDo: the loop of a function whose body is a decision: the
// body up to the decision in the before region, the region that loops in
// the after region, and the region that exits after the loop.
module;
// llvm_unreachable is a macro, which no import carries.
#include "llvm/Support/ErrorHandling.h"

export module idr.tail:whileDo;

import idr.mlir;
import idr.dialect;

import :decision;

using namespace mlir;

namespace idr::tail {

// The loop of a function whose body is a decision (decisionOf).
class WhileDo {
public:
  WhileDo(func::FuncOp fn, Decision decision, OpBuilder &b) : fn(fn), decision(decision), b(b) {}

  // Builds the loop, or leaves the function as it was and fails when what
  // the regions need from the body cannot pass from one iteration to the
  // next as plain values: values that hold no reference.
  FailureOr<scf::WhileOp> build();

private:
  // The value `scope` sees for `value` of the body: the before region's
  // argument, the after region's, or the loop's result.
  enum class Scope { Before, After, Exit };
  Value in(Value value, Scope scope);
  // Where `scope`'s code begins: the before or after block, or the
  // function's block after the loop.
  Block *blockOf(Scope scope);
  // The `i1` that holds when the decision takes the region that loops,
  // built at the end of the before block.
  Value continues();
  // Moves the ops of `region` to the end of `scope`'s block, its arguments
  // (a case's fields) read from the scrutinee, and returns its terminator.
  Operation *inlineRegion(Region &region, Scope scope);

  func::FuncOp fn;
  Decision decision;
  OpBuilder &b;
  scf::WhileOp loop;
  // The arguments that change from one call to the next, by position.
  SmallVector<unsigned> carried;
  // What the body computes before the decision and the regions use: carried
  // by the loop after the arguments.
  SmallVector<Value> passed;
};

Block *WhileDo::blockOf(Scope scope) {
  switch (scope) {
  case Scope::Before:
    return loop.getBeforeBody();
  case Scope::After:
    return loop.getAfterBody();
  case Scope::Exit:
    return loop->getBlock();
  }
  llvm_unreachable("a scope");
}

Value WhileDo::in(Value value, Scope scope) {
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
    if (scope == Scope::Before)
      return value;
    slot = static_cast<unsigned>(carried.size()) + static_cast<unsigned>(it - passed.begin());
  }
  switch (scope) {
  case Scope::Before:
    return loop.getBeforeArguments()[slot];
  case Scope::After:
    return loop.getAfterArguments()[slot];
  case Scope::Exit:
    return loop.getResult(slot);
  }
  llvm_unreachable("a scope");
}

Value WhileDo::continues() {
  Operation *match = decision.match;
  bool loopsFirst = decision.loops->getRegionNumber() == 0;
  Location loc = match->getLoc();
  b.setInsertionPointToEnd(loop.getBeforeBody());
  // `(x == k) == loopsFirst`: region 0 is the case k, region 1 the default.
  auto test = [&](Value x, IntegerAttr k) -> Value {
    auto predicate = loopsFirst ? arith::CmpIPredicate::eq : arith::CmpIPredicate::ne;
    // A test of a flag is the flag, or the comparison it holds, turned
    // around.
    if (auto extended = x.getDefiningOp<arith::ExtUIOp>();
        extended && extended.getIn().getType().isInteger(1) && k.getValue().ule(1)) {
      x = extended.getIn();
      k = b.getIntegerAttr(x.getType(), k.getValue().trunc(1));
    }
    if (x.getType().isInteger(1)) {
      bool whenSet = (predicate == arith::CmpIPredicate::eq) == k.getValue().isOne();
      if (whenSet)
        return x;
      if (auto compare = x.getDefiningOp<arith::CmpIOp>())
        return arith::CmpIOp::create(b, loc, arith::invertPredicate(compare.getPredicate()),
                                     compare.getLhs(), compare.getRhs());
    }
    Value key = arith::ConstantOp::create(b, loc, k);
    return arith::CmpIOp::create(b, loc, predicate, x, key);
  };
  if (auto lit = dyn_cast<idr::MatchLitOp>(match))
    return test(in(lit.getScrutinee(), Scope::Before), cast<IntegerAttr>(lit.getCases()[0]));
  // Region 0 is the case of a constructor; region 1 is the default, or the
  // last case, which idr-lower also takes for any constructor Idris proved
  // impossible.
  auto sum = cast<idr::MatchOp>(match);
  Value scrutinee = in(sum.getScrutinee(), Scope::Before);
  auto name = cast<FlatSymbolRefAttr>(sum.getCases()[0]).getAttr();
  auto ctors = idr::lookupData(sum, scrutinee.getType()).getCtors();
  auto ctor = llvm::find_if(ctors, [&](idr::CtorOp c) { return c.getSymNameAttr() == name; });
  Value tag = idr::TagOp::create(b, loc, scrutinee);
  return test(tag, b.getI64IntegerAttr(ctor - ctors.begin()));
}

Operation *WhileDo::inlineRegion(Region &region, Scope scope) {
  Block &from = region.front();
  Block *to = blockOf(scope);
  // Uses of the body's values in the region see this scope's.
  region.walk([&](Operation *op) {
    for (OpOperand &operand : op->getOpOperands())
      operand.set(in(operand.get(), scope));
  });
  if (auto sum = dyn_cast<idr::MatchOp>(decision.match); sum && from.getNumArguments() != 0) {
    Value scrutinee = in(sum.getScrutinee(), scope);
    b.setInsertionPointToEnd(to);
    unsigned index = region.getRegionNumber();
    // The default region has the scrutinee itself back.
    FlatSymbolRefAttr ctor;
    idr::CtorOp decl;
    if (index < sum.getCases().size()) {
      ctor = cast<FlatSymbolRefAttr>(sum.getCases()[index]);
      decl = idr::lookupCtor(idr::lookupData(sum, scrutinee.getType()), ctor.getValue());
    }
    for (BlockArgument field : from.getArguments()) {
      if (field.use_empty())
        continue;
      Value value = scrutinee;
      if (ctor)
        value = idr::FieldOp::create(
            b, field.getLoc(), idr::fieldType(scrutinee.getType(), decl.getFieldType(field.getArgNumber())),
            scrutinee, ctor, b.getI64IntegerAttr(field.getArgNumber()));
      field.replaceAllUsesWith(idr::heldAs(b, field.getLoc(), value, field.getType()));
    }
  }
  to->getOperations().splice(to->end(), from.getOperations());
  return to->getTerminator();
}

FailureOr<scf::WhileOp> WhileDo::build() {
  Block &entry = fn.getBody().front();
  Operation *match = decision.match;
  // An argument the call passes unchanged is not carried, unless the call
  // consumes a reference of it: then each iteration takes one, which the
  // yield to the next must consume as the call did.
  auto call = cast<func::CallOp>(decision.loops->front().getTerminator()->getPrevNode());
  for (BlockArgument arg : entry.getArguments()) {
    unsigned index = arg.getArgNumber();
    bool consumed = idr::isOwned(arg.getType());
    if (call.getOperand(index) != arg || consumed)
      carried.push_back(index);
  }

  // The body before the decision: what depends only on arguments that do
  // not change, and holds no reference, runs once before the loop; the rest
  // runs in every iteration.
  SmallVector<Operation *> hoisted, repeated;
  llvm::SmallPtrSet<Operation *, 16> outside;
  auto invariant = [&](Value value) {
    if (auto arg = dyn_cast<BlockArgument>(value))
      return arg.getOwner() == &entry && !llvm::is_contained(carried, arg.getArgNumber());
    return outside.contains(value.getDefiningOp());
  };
  for (Operation &op : llvm::make_range(entry.begin(), match->getIterator())) {
    bool once = op.getNumRegions() == 0 && isMemoryEffectFree(&op) &&
                llvm::all_of(op.getOperands(), invariant) &&
                llvm::none_of(op.getResults(), [&](Value r) { return idr::isOwned(r.getType()); });
    if (once)
      outside.insert(&op);
    (once ? hoisted : repeated).push_back(&op);
  }
  // What the regions use of the repeated part passes from the before
  // region to the rest as a plain value, one that holds no reference; the
  // scrutinee of a match on a constructor too, whose fields the regions
  // read.
  llvm::SetVector<Value> needed;
  for (Region *region : {decision.loops, decision.exits})
    region->walk([&](Operation *op) {
      for (Value operand : op->getOperands())
        if (Operation *def = operand.getDefiningOp();
            def && def->getBlock() == &entry && !outside.contains(def))
          needed.insert(operand);
    });
  if (auto sum = dyn_cast<idr::MatchOp>(match))
    if (Operation *def = sum.getScrutinee().getDefiningOp(); def && !outside.contains(def))
      needed.insert(sum.getScrutinee());
  if (llvm::any_of(needed, [&](Value value) { return idr::isOwned(value.getType()); }))
    return failure();
  // The before region passes every argument it has on to the rest, as the
  // uplift expects. A world or linear argument that the decision's code
  // already takes, or that the decision itself takes apart, would then be
  // taken twice.
  auto takenBefore = [&](unsigned index) {
    BlockArgument arg = entry.getArgument(index);
    return idr::quantityOf(arg.getType()) == idr::Quantity::One &&
           llvm::any_of(arg.getUsers(), [&](Operation *user) {
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
  b.setInsertionPoint(match);
  loop = scf::WhileOp::create(b, loc, through, initValues);
  SmallVector<Location> locs(through.size(), loc);
  Block *before = b.createBlock(&loop.getBefore(), {}, types, ArrayRef(locs).take_front(types.size()));
  b.createBlock(&loop.getAfter(), {}, through, locs);
  for (Operation *op : repeated) {
    op->moveBefore(before, before->end());
    op->walk([&](Operation *inner) {
      for (OpOperand &operand : inner->getOpOperands())
        operand.set(in(operand.get(), Scope::Before));
    });
  }
  Value go = continues();
  SmallVector<Value> forwarded(loop.getBeforeArguments());
  llvm::append_range(forwarded, passed);
  scf::ConditionOp::create(b, match->getLoc(), go, forwarded);

  // The region that loops: its call's arguments are the next iteration's.
  Operation *yield = inlineRegion(*decision.loops, Scope::After);
  auto next = cast<func::CallOp>(yield->getPrevNode());
  b.setInsertionPoint(yield);
  SmallVector<Value> values;
  for (unsigned index : carried)
    values.push_back(next.getOperand(index));
  scf::YieldOp::create(b, yield->getLoc(), values);
  yield->erase();
  next.erase();
  if (!fn->hasAttr("idr.total")) {
    b.setInsertionPointToStart(loop.getAfterBody());
    idr::MayLoopOp::create(b, loc);
  }

  // The region that exits runs after the loop; the function returns what
  // it yields.
  // The region's ops go after the return, which then makes way for them.
  Operation *ret = entry.getTerminator();
  Operation *exit = inlineRegion(*decision.exits, Scope::Exit);
  ret->erase();
  b.setInsertionPoint(exit);
  if (auto result = dyn_cast<idr::YieldOp>(exit)) {
    func::ReturnOp::create(b, result.getLoc(), result.getResults());
  } else {
    // A region that crashes: the function never returns there.
    ub::UnreachableOp::create(b, exit->getLoc());
  }
  exit->erase();
  match->erase();
  // What only the decision read (a flag widened for it, a comparison
  // turned around) is left over. The ops are listed first: a reverse
  // iterator refers to the op after the one it yields, which may go too.
  SmallVector<Operation *> body =
      llvm::map_to_vector(before->without_terminator(), [](Operation &op) { return &op; });
  for (Operation *op : llvm::reverse(body))
    if (isOpTriviallyDead(op))
      op->erase();
  return loop;
}

} // namespace idr::tail
