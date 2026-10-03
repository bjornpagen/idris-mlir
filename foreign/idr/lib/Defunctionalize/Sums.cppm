// idr.defunctionalize:sums: closures of known labels become sums.
//
// The analysis is a sparse forward dataflow analysis on MLIR's framework,
// interprocedural, whose lattice is the set of labels (functions) a
// `!idr.fn` value may hold, or unknown. Values reach fields through one
// lattice anchor per (data type, constructor, field), written by `idr.con`
// and constants and read by `idr.field` and the regions of `idr.match`.
// The framework follows only calls of symbols, so the pass joins the rest
// itself: the entry arguments of a function get the captures of its closures
// (`idr.closure` ops and `#idr.closure` constants) and the arguments of every
// `idr.apply` that may call it, and an `idr.apply` gets the results of every
// label it may call.
//
// Sums are keyed by (closure type, label set), not by type alone. Every
// slot that holds a closure (a value, a function argument or result, a
// field of a constructor) has the key of its type and the labels the
// analysis found for it; a closure or constant used only where one larger
// set is expected takes that set. A key is converted when its labels are
// known, not empty and fit the type. Its values belong to a new sum
// `@fn$<n>`, unboxed unless the key is on a cycle of "a capture of one of
// its labels holds, directly or through unboxed data, a value of key K":
// only such a cycle makes an unboxed sum infinite, and a box ends it, as a
// recursive set of lambdas is a recursive datatype. A closure of type T may
// capture another closure of type T without a cycle when the captured one
// holds other labels (a state monad's bind captures a bind of different
// lambdas). The sums are numbered by first appearance in the module, with
// one constructor per
// label whose fields are the label's captures, each with the key of that
// capture (the label's entry argument): `idr.closure @f(...)` becomes
// `idr.con @fn$n::@f(...)`, a closure constant the matching constructor
// constant, and `idr.apply` an `idr.match` over the labels the callee may
// hold, each region calling its label.
//
// Where a value flows from a slot into one of another key (call operand to
// argument, return to result, yield to match result, field, capture, and
// through a rewritten apply to and from its labels), a coercion is
// inserted: an `idr.match` that rebuilds each label in the other sum, or as
// an `idr.closure` when the other key stays a closure. A value the analysis
// never reaches (the empty set) becomes `ub.poison`. A key stays a closure
// when a value can reach it only as a closure, and then every label that
// can reach it keeps the closure type's signature: its argument and result
// slots of closure type stay closures too: in a whole program that is only
// a key whose labels the analysis cannot know.
export module idr.defunctionalize:sums;

import idr.mlir;

import :analysis;
import :closures;
import :converter;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

// What `defunctionalize` made of the module's keys: the sums, and the keys
// that stay closures.
export struct Defunctionalized {
  uint64_t sums = 0;
  uint64_t closures = 0;
};

// Converts every key of `module` it can into a sum. Fails when the analysis
// fails.
export FailureOr<Defunctionalized> defunctionalize(ModuleOp top) {
  Module module(top);
  module.gather();
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
  loadBaselineAnalyses(solver);
  solver.load<LabelAnalysis>(module);
  if (failed(solver.initializeAndRun(top)))
    return failure();
  Converter converter(module, solver);
  converter.run();
  Defunctionalized done;
  done.sums = converter.converted.size();
  done.closures = converter.keys.size() - converter.converted.size();
  return done;
}

} // namespace idr::defunctionalize
