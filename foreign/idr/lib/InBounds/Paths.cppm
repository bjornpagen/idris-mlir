// idr.inbounds:paths: what the path to a guard says of its integers. Each
// op enclosing the guard ran the region it is in for a reason: a match
// took the case of its scrutinee's value, an scf.if its condition's side, a
// loop's body runs while its condition held and at an index within its
// bounds. And a guard of an index before it on every path (earlier in its
// block, or in an enclosing one) ran without crashing, so that index was
// within its length. The facts are of the values as they are at the guard:
// each enclosing op's operands, and the values it forwards, dominate it.
export module idr.inbounds:paths;

import idr.mlir;
import idr.dialect;

import :guards;
import :linear;
import :system;

using namespace mlir;
using llvm::DynamicAPInt;

namespace idr::inbounds {

namespace {

// The guards of an index among `block`'s ops before `end` (all of them
// when null) held: each crashes the run where its index is outside its
// length, whether it is left to check or proven and erased. Its array's
// length is one the sizes in scope may be.
void guardsBefore(Block &block, Operation *end, System &system) {
  for (Operation &op : block) {
    if (&op == end)
      return;
    auto guard = dyn_cast<CheckInBoundsOp>(op);
    if (!guard)
      continue;
    std::optional<Value> array = guardedArray(guard);
    Linear i = system.of(guard.getIndex());
    system.atLeastZero(i);
    system.atLeastZero((system.sizeOf(guard.getLength(), array) - i).plus(-1));
    if (array)
      system.lengthOf(*array);
  }
}

// `value` was each of `literals` (a case taken), or none of them (the
// default taken).
void assumeCase(System &system, Value value, ArrayRef<APInt> literals, bool isOne) {
  if (!system.known(value))
    return;
  Value condition;
  int64_t whenTrue = 1;
  if (value.getType().isInteger(1)) {
    condition = value;
  } else if (auto ext = value.getDefiningOp<arith::ExtUIOp>(); ext && ext.getIn().getType().isInteger(1)) {
    condition = ext.getIn();
  } else if (auto sext = value.getDefiningOp<arith::ExtSIOp>(); sext && sext.getIn().getType().isInteger(1)) {
    condition = sext.getIn();
    whenTrue = -1;
  }
  if (condition) {
    // Of the two values a condition stands for, those the case allows.
    // An i1 literal is the condition itself, true as 1.
    auto allowed = [&](int64_t v) {
      bool listed = llvm::any_of(literals, [&](const APInt &k) {
        return (k.getBitWidth() == 1 ? int64_t(k.getZExtValue()) : k.getSExtValue()) == v;
      });
      return isOne ? listed : !listed;
    };
    bool t = allowed(whenTrue), f = allowed(0);
    if (!t && !f)
      system.impossible();
    else if (t != f)
      system.assume(condition, t);
    return;
  }
  if (!isColumn(value))
    return;
  if (isOne) {
    system.zero(system.of(value) - Linear::constantOf(DynamicAPInt(literals.front().getSExtValue())));
    return;
  }
  // None of the literals: the range loses each at its ends.
  std::optional<Bounds> bounds = system.rangeOf(value);
  if (!bounds)
    return;
  auto [lo, hi] = *bounds;
  auto listed = [&](const DynamicAPInt &v) {
    return llvm::any_of(literals,
                        [&](const APInt &k) { return DynamicAPInt(k.getSExtValue()) == v; });
  };
  while (lo <= hi && listed(lo))
    ++lo;
  while (hi >= lo && listed(hi))
    --hi;
  if (lo > hi)
    return system.impossible();
  system.within(system.of(value), lo, hi);
}

void caseTaken(MatchLitOp match, Region &region, System &system) {
  SmallVector<APInt> literals;
  for (Attribute literal : match.getCases()) {
    auto integer = dyn_cast<IntegerAttr>(literal);
    if (!integer)
      return;
    literals.push_back(integer.getValue());
  }
  unsigned number = region.getRegionNumber();
  if (number < literals.size())
    assumeCase(system, match.getScrutinee(), literals[number], true);
  else
    assumeCase(system, match.getScrutinee(), literals, false);
}

// The after region of `loop` runs on what its condition forwarded, once
// the condition held, after its before block ran.
void whileBody(scf::WhileOp loop, System &system) {
  scf::ConditionOp condition = loop.getConditionOp();
  for (auto [arg, forwarded] : llvm::zip_equal(loop.getAfterArguments(), condition.getArgs()))
    if (isColumn(arg))
      system.zero(system.of(arg) - system.of(forwarded));
  system.assume(condition.getCondition(), true);
  guardsBefore(loop.getBefore().front(), nullptr, system);
}

// An scf.for's body runs at lb, lb + step, ... below ub, for a step above 0.
void forBody(scf::ForOp loop, System &system) {
  APInt step;
  if (loop.getUnsignedCmp() || !matchPattern(loop.getStep(), m_ConstantInt(&step)) ||
      !step.isStrictlyPositive() || !isColumn(loop.getInductionVar()))
    return;
  Linear iv = system.of(loop.getInductionVar());
  system.atLeastZero(iv - system.of(loop.getLowerBound()));
  system.atLeastZero((system.of(loop.getUpperBound()) - iv).plus(-1));
}

void bodyFacts(Operation *parent, Region &region, System &system) {
  if (auto match = dyn_cast<MatchLitOp>(parent))
    return caseTaken(match, region, system);
  if (auto branch = dyn_cast<scf::IfOp>(parent))
    return system.assume(branch.getCondition(), region.getRegionNumber() == 0);
  if (auto loop = dyn_cast<scf::WhileOp>(parent)) {
    if (&region == &loop.getAfter())
      whileBody(loop, system);
    return;
  }
  if (auto loop = dyn_cast<scf::ForOp>(parent))
    return forBody(loop, system);
  // Element 0 is the fill; the body makes the others.
  if (auto generate = dyn_cast<ArrayGenerateOp>(parent)) {
    Linear i = system.of(generate.getBody().front().getArgument(0));
    system.atLeastZero(Linear(i).plus(-1));
    system.atLeastZero((system.of(generate.getSize()) - i).plus(-1));
    return;
  }
  if (auto fold = dyn_cast<ArrayFoldOp>(parent)) {
    Linear i = system.of(fold.getBody().front().getArgument(2));
    system.atLeastZero(i);
    system.atLeastZero((system.lengthOf(fold.getArray()) - i).plus(-1));
  }
}

} // namespace

// Whether a value is known at `op`: computed before it on every path, or in
// the before block of a loop whose body holds `op`, which runs right after
// that block, on what it computed.
export std::function<bool(Value)> knownAt(Operation *op, DominanceInfo &dominance) {
  return [op, &dominance](Value value) {
    if (dominance.properlyDominates(value, op))
      return true;
    Block *block = value.getParentBlock();
    auto loop = dyn_cast_or_null<scf::WhileOp>(block->getParentOp());
    return loop && block == &loop.getBefore().front() &&
           loop.getAfter().isAncestor(op->getParentRegion());
  };
}

// Adds what the path from its function's entry to `at` says.
export void pathFacts(Operation *at, System &system) {
  Operation *op = at;
  while (Operation *parent = op->getParentOp()) {
    guardsBefore(*op->getBlock(), op, system);
    if (isa<FunctionOpInterface>(parent))
      return;
    bodyFacts(parent, *op->getParentRegion(), system);
    op = parent;
  }
}

} // namespace idr::inbounds
