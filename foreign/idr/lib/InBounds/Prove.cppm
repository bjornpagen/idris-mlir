// idr.inbounds:prove: each access is proven when no integers satisfy what
// is known at it together with an index outside its array, `i < 0` or
// `i >= length`. What is known: the path to it (paths), the definitions of
// the integers it compares (system), and every integer in scope that is the
// length of an array in scope (lengths). MLIR's Presburger library decides
// the two systems exactly, so a proof is a proof over the integers and a
// failure only leaves the check in place.
export module idr.inbounds:prove;

import idr.mlir;
import idr.dialect;
import idr.narrow;

import :joins;
import :linear;
import :lengths;
import :paths;
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

// Whether `index` is within `array` whenever `access` runs.
bool provenInBounds(Operation *access, Value array, Value index, DataFlowSolver &solver,
                    DominanceInfo &dominance, Lengths &lengths) {
  if (!isColumn(index))
    return false;
  // A value is known at the access when it is computed before it on every
  // path, or in the before block of a loop whose body holds the access: the
  // body runs right after that block, on what it computed.
  auto admissible = [&](Value value) {
    if (dominance.properlyDominates(value, access))
      return true;
    Block *block = value.getParentBlock();
    auto loop = dyn_cast_or_null<scf::WhileOp>(block->getParentOp());
    return loop && block == &loop.getBefore().front() &&
           loop.getAfter().isAncestor(access->getParentRegion());
  };
  System system(solver, admissible);
  Linear i = system.of(index);
  Linear length = system.lengthOf(array);
  pathFacts(access, system);
  // A length relation holds where both values are in scope, which a value
  // of a loop's before block is not in its body.
  for (Value root : system.roots()) {
    if (!dominance.properlyDominates(root, access))
      continue;
    for (Value size : system.values())
      if (size.getType().isInteger(64) && dominance.properlyDominates(size, access) &&
          lengths.related(size, root))
        system.lengthIs(size, root);
  }
  return system.emptyWith(Linear().plus(i, DynamicAPInt(-1)).plus(-1)) &&
         system.emptyWith(i - length);
}

} // namespace

// Marks `in_bounds` every access of `module` proven within its array. The
// proofs are all made before any is marked, though a mark changes none:
// an access before another ran within its array either way.
export FailureOr<Proved> prove(ModuleOp module) {
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
  if (failed(narrow::runSolver(solver, module)))
    return failure();
  DominanceInfo dominance(module);
  Lengths lengths(module);
  SmallVector<Operation *> proven;
  Proved done;
  module.walk([&](Operation *op) {
    bool in = false;
    if (auto get = dyn_cast<ArrayGetOp>(op))
      in = get.getInBounds() ||
           provenInBounds(op, get.getArray(), get.getIndex(), solver, dominance, lengths);
    else if (auto set = dyn_cast<ArraySetOp>(op))
      in = set.getInBounds() ||
           provenInBounds(op, set.getArray(), set.getIndex(), solver, dominance, lengths);
    else
      return;
    if (in)
      proven.push_back(op);
    ++(in ? done.proved : done.checked);
  });
  for (Operation *op : proven) {
    if (auto get = dyn_cast<ArrayGetOp>(op))
      get.setInBounds(true);
    else
      cast<ArraySetOp>(op).setInBounds(true);
  }
  return done;
}

} // namespace idr::inbounds
