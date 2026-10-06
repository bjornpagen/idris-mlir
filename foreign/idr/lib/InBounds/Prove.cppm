// idr.inbounds:prove: each access is proven when no integers satisfy what
// is known at it together with an index outside its array, `i < 0` or
// `i >= length`. What is known: the path to it (paths), the definitions of
// the integers it compares (system), the bounds its loops keep their
// counters in (induction), and every integer in scope that is the length of
// an array in scope (lengths). MLIR's Presburger library decides
// the two systems exactly, so a proof is a proof over the integers and a
// failure only leaves the check in place.
export module idr.inbounds:prove;

import idr.mlir;
import idr.dialect;
import idr.narrow;

import :induction;
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

// Whether `index` is within `array` whenever `access` runs, with what
// `carried` says of loop counters. A system no loop bound reached is one
// already found wanting, so it is not decided again.
bool provenInBounds(Operation *access, Value array, Value index, DataFlowSolver &solver,
                    DominanceInfo &dominance, Lengths &lengths, CarriedBounds carried) {
  if (!isColumn(index))
    return false;
  bool bounded = !carried;
  System system(solver, knownAt(access, dominance), [&](Value value) -> std::optional<Bounds> {
    std::optional<Bounds> bounds = carried ? carried(value) : std::nullopt;
    bounded |= bounds.has_value();
    return bounds;
  });
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
  return bounded && system.emptyWith(Linear().plus(i, DynamicAPInt(-1)).plus(-1)) &&
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
  Induction induction(solver, dominance);
  SmallVector<Operation *> proven;
  Proved done;
  module.walk([&](Operation *op) {
    auto get = dyn_cast<ArrayGetOp>(op);
    auto set = dyn_cast<ArraySetOp>(op);
    if (!get && !set)
      return;
    auto [array, index] = get ? std::pair{get.getArray(), get.getIndex()}
                              : std::pair{set.getArray(), set.getIndex()};
    auto proves = [&](CarriedBounds carried) {
      return provenInBounds(op, array, index, solver, dominance, lengths, std::move(carried));
    };
    // The bounds the loops keep their counters in cost a system per back
    // edge, so they are proven only for an access that needs them.
    bool in = (get ? get.getInBounds() : set.getInBounds()) || proves(nullptr) ||
              proves(induction.asCarried());
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
