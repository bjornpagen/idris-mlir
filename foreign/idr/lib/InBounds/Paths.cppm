// idr.inbounds:paths: what the path to an access says of its integers. Each
// op enclosing the access ran the region it is in for a reason: a match
// took the case of its scrutinee's value, an scf.if its condition's side, a
// loop's body runs while its condition held and at an index within its
// bounds. And an access before it on every path (earlier in its block, or
// in an enclosing one) ran without crashing, so its index was within its
// array. The facts are of the values as they are at the access: each
// enclosing op's operands, and the values it forwards, dominate it.
export module idr.inbounds:paths;

import idr.mlir;
import idr.dialect;

import :linear;
import :system;

using namespace mlir;
using llvm::DynamicAPInt;

namespace idr::inbounds {

namespace {

// The accesses among `block`'s ops before `end` (all of them when null)
// ran, each checked or proven.
void accessesBefore(Block &block, Operation *end, System &system) {
  for (Operation &op : block) {
    if (&op == end)
      return;
    if (auto get = dyn_cast<ArrayGetOp>(op))
      system.accessed(get.getArray(), get.getIndex());
    else if (auto set = dyn_cast<ArraySetOp>(op))
      system.accessed(set.getArray(), set.getIndex());
  }
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
    system.assumeCase(match.getScrutinee(), literals[number], true);
  else
    system.assumeCase(match.getScrutinee(), literals, false);
}

// The after region of `loop` runs on what its condition forwarded, once
// the condition held, after its before block ran.
void whileBody(scf::WhileOp loop, System &system) {
  scf::ConditionOp condition = loop.getConditionOp();
  for (auto [arg, forwarded] : llvm::zip_equal(loop.getAfterArguments(), condition.getArgs()))
    if (isColumn(arg))
      system.zero(system.of(arg) - system.of(forwarded));
  system.assume(condition.getCondition(), true);
  accessesBefore(loop.getBefore().front(), nullptr, system);
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

// Adds what the path from its function's entry to `access` says.
export void pathFacts(Operation *access, System &system) {
  Operation *op = access;
  while (Operation *parent = op->getParentOp()) {
    accessesBefore(*op->getBlock(), op, system);
    if (isa<FunctionOpInterface>(parent))
      return;
    bodyFacts(parent, *op->getParentRegion(), system);
    op = parent;
  }
}

} // namespace idr::inbounds
