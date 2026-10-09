// idr.inbounds:prove: a guard is erased when its condition holds wherever
// it runs, so it can never crash. A guard of an index holds when no
// integers satisfy what is known at it together with an index outside its
// length, `i < 0` or `i >= length`. What is known: the path to it (paths),
// the definitions of the integers it compares (system), the bounds its loops
// keep their counters in (induction), and every integer in scope that is the
// length of an array in scope (lengths). MLIR's Presburger library decides
// the two systems exactly, so a proof is a proof over the integers and a
// failure only leaves the guard in place. Any guard also holds when one of
// its kind on the same operands runs before it on every path, and a guard of
// an integer when the ranges MLIR's integer range analysis gives its
// operands satisfy its condition.
export module idr.inbounds:prove;

import idr.mlir;
import idr.dialect;
import idr.narrow;

import :guards;
import :induction;
import :joins;
import :linear;
import :lengths;
import :masks;
import :paths;
import :quotients;
import :system;

using namespace mlir;
using llvm::DynamicAPInt;
using namespace mlir::dataflow;

namespace idr::inbounds {

export struct Proved {
  unsigned proved = 0;
  unsigned checked = 0;
};

namespace {

// Whether `guard`'s index is within its length whenever it runs, with what
// `carried` says of loop counters. A system no loop bound reached is one
// already found wanting, so it is not decided again.
bool provenInBounds(CheckInBoundsOp guard, DataFlowSolver &solver, DominanceInfo &dominance,
                    Lengths &lengths, CarriedBounds carried) {
  Value index = guard.getIndex();
  bool bounded = !carried;
  // A length relation holds where both values are in scope, which a value
  // of a loop's before block is not in its body.
  auto related = [&](Value size, Value array) {
    return dominance.properlyDominates(size, guard) &&
           dominance.properlyDominates(arrayRoot(array), guard) && lengths.related(size, array);
  };
  System system(
      solver, knownAt(guard, dominance),
      [&](Value value) -> std::optional<Bounds> {
        std::optional<Bounds> bounds = carried ? carried(value) : std::nullopt;
        bounded |= bounds.has_value();
        return bounds;
      },
      related);
  std::optional<Value> array = guardedArray(guard);
  Linear i = system.of(index);
  Linear length = system.sizeOf(guard.getLength(), array);
  if (array)
    system.lengthOf(*array);
  pathFacts(guard, system);
  for (Value root : system.roots()) {
    if (!dominance.properlyDominates(root, guard))
      continue;
    for (Value size : system.values())
      if (size.getType().isInteger(64) && related(size, root))
        system.lengthIs(size, root);
  }
  // Quotients are read after the path and the lengths, which are what can
  // show the dividend is non-negative. A mask is read after the same facts:
  // the path is what bounds a shift, and the length relation is what says
  // the array has that capacity.
  relateQuotients(system);
  if (array)
    relateMask(system, lengths, dominance, guard, *array, index);
  return bounded && system.emptyWith(Linear().plus(i, DynamicAPInt(-1)).plus(-1)) &&
         system.emptyWith(i - length);
}

// Whether a guard of the same kind on the same operands runs before `guard`
// on every path to it. The operands are the same values there, so that one
// checked this one's condition and did not crash.
bool checkedBefore(GuardOpInterface guard, DominanceInfo &dominance) {
  for (Operation *other : guard.getGuarded().getUsers())
    if (other != guard && other->getName() == guard->getName() &&
        llvm::equal(other->getOperands(), guard->getOperands()) &&
        dominance.properlyDominates(other, guard))
      return true;
  return false;
}

// Whether the ranges the analysis gives `guard`'s integer operands satisfy
// its condition. A range holds of every value its SSA value takes, so the
// condition holds wherever the guard runs. A value the analysis never
// reached proves nothing.
bool provenByRanges(Operation *guard, DataFlowSolver &solver) {
  auto range = [&](Value value) -> std::optional<ConstantIntRanges> {
    if (!isa<IntegerType>(value.getType()))
      return std::nullopt;
    return narrow::rangeOf(solver, value);
  };
  if (auto nonzero = dyn_cast<CheckNonzeroOp>(guard)) {
    std::optional<ConstantIntRanges> v = range(nonzero.getValue());
    return v && (!v->umin().isZero() || v->smin().isStrictlyPositive() || v->smax().isNegative());
  }
  if (auto byte = dyn_cast<CheckByteOp>(guard)) {
    std::optional<ConstantIntRanges> v = range(byte.getValue());
    return v && v->smin().isNonNegative() && v->smax().sle(255);
  }
  if (auto index = dyn_cast<CheckInBoundsOp>(guard)) {
    std::optional<ConstantIntRanges> i = range(index.getIndex());
    std::optional<ConstantIntRanges> n = range(index.getLength());
    return i && n && i->smin().isNonNegative() && i->smax().slt(n->smin());
  }
  if (auto bytes = dyn_cast<CheckRangeOp>(guard)) {
    std::optional<ConstantIntRanges> offset = range(bytes.getOffset());
    std::optional<ConstantIntRanges> count = range(bytes.getCount());
    std::optional<ConstantIntRanges> size = range(bytes.getSize());
    if (!offset || !count || !size || !offset->smin().isNonNegative() ||
        !count->smin().isNonNegative())
      return false;
    // The end of the farthest range, in a word one bit wider, where the sum
    // of two non-negative words cannot overflow.
    unsigned wide = offset->smax().getBitWidth() + 1;
    APInt end = offset->smax().sext(wide) + count->smax().sext(wide);
    return end.sle(size->smin().sext(wide));
  }
  return false;
}

} // namespace

// Erases every guard of `module` that can never crash. Each is judged on
// the module as it is, and those that hold are erased together: in every
// run each of them gives its operand, so the module without them runs the
// same way. A guard erased this way is still a fact of the guards after it,
// which held either way.
export FailureOr<Proved> prove(ModuleOp module) {
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
  if (failed(narrow::runSolver(solver, module)))
    return failure();
  DominanceInfo dominance(module);
  Lengths lengths(module, solver);
  Induction induction(solver, dominance);
  SmallVector<GuardOpInterface> proven;
  Proved done;
  module.walk([&](GuardOpInterface guard) {
    Operation *op = guard;
    auto index = dyn_cast<CheckInBoundsOp>(op);
    auto proves = [&](CarriedBounds carried) {
      return provenInBounds(index, solver, dominance, lengths, std::move(carried));
    };
    // The bounds the loops keep their counters in cost a system per back
    // edge, so they are proven only for a guard that needs them.
    bool holds = checkedBefore(guard, dominance) || provenByRanges(op, solver) ||
                 (index && (proves(nullptr) || proves(induction.asCarried())));
    if (holds)
      proven.push_back(guard);
    ++(holds ? done.proved : done.checked);
  });
  for (GuardOpInterface guard : proven) {
    guard->getResult(0).replaceAllUsesWith(guard.getGuarded());
    guard->erase();
  }
  return done;
}

} // namespace idr::inbounds
