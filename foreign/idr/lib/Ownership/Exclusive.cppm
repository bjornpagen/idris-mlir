// idr.ownership:exclusive: exclusivity: which owned values hold the only
// reference to every cell of their cell graph that a take could hand out,
// so that taking them apart needs no count test, and building in their
// cells no null test. Those are the cells with fields; static data built
// only of atoms has none to hand out (an atom has no fields to take, an
// unboxed sum no cell), no count reaches it and nothing frees or writes it,
// so it is in every exclusive tree however many hold it (reachesOnlyAtoms).
//
// In the owned stage a reference is duplicated only by idr.dup, so
// exclusivity is provenance: a value is exclusive when it is a constructor
// whose box fields are exclusive, a field an exclusive value was taken apart
// into (the token of that take too), a call's result that every return
// makes exclusive, a parameter every caller passes exclusive, or a copy of
// static data built only of atoms. So the pair of empty lists that span and
// splitAt give at the end of their input joins the pair they build around
// an exclusive one, and the join stays exclusive. Any other dup or
// constant, a stack cell and a value from a caller the module does not show
// are shared. The analysis is a sparse forward dataflow on MLIR's solver,
// optimistic as SCCP is: a value is exclusive until a path shares it, which
// is sound by induction on the run. What it proves is written into the
// types (`!idr.excl<T>`), which every later pass keeps and the owned
// stage's verifier checks.
export module idr.ownership:exclusive;

import idr.mlir;

import :commit;
import :exclusiveanalysis;
import :noconstants;
import :sharetainted;
import :specialize;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::ownership {

// Exclusivity: the owned values that hold the only reference to every cell
// they reach get the excl grade, and an exclusive value given to an owned
// position is shared into it (idr.share). Returns how many values are
// exclusive.
export FailureOr<unsigned> inferExclusive(ModuleOp module) {
  // A clone names itself (idr.clone) without calling it, which the solver
  // would take for a caller it cannot see; nothing after idr-rc reads it.
  for (auto fn : module.getOps<func::FuncOp>())
    fn->removeAttr("idr.clone");
  shareTainted(module);
  Specialize::Copies copies;
  // Every round redirects a call for good, so the rounds are bounded by
  // the calls; a round past that is a bug here.
  unsigned calls = 0;
  module.walk([&](func::CallOp) { ++calls; });
  for (unsigned round = 0;; ++round) {
    DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
    solver.load<DeadCodeAnalysis>();
    solver.load<NoConstants>();
    solver.load<ExclusiveAnalysis>();
    if (failed(solver.initializeAndRun(module)))
      return failure();
    if (round <= calls && Specialize(module, solver, copies).run())
      continue;
    if (round > calls)
      return module.emitError("idr-rc: specializing on exclusivity did not settle"), failure();
    FailureOr<unsigned> exclusive = Commit(module, solver).run();
    if (failed(exclusive))
      return failure();
    // A function every call of which went to its copy is unused.
    for (auto [original, copy] : copies)
      if (SymbolTable::symbolKnownUseEmpty(original, module))
        original->erase();
    return exclusive;
  }
}

} // namespace idr::ownership
