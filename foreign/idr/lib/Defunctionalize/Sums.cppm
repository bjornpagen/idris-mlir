// idr.defunctionalize:sums: closures and suspensions of known labels become
// sums.
//
// The analysis is a sparse forward dataflow analysis on MLIR's framework,
// interprocedural, whose lattice is the set of labels (functions) a
// `!idr.fn` or `!idr.lazy` value may hold, or unknown. Values reach fields
// through one lattice anchor per (data type, constructor, field), written by
// `idr.con` and constants and read by `idr.field` and the regions of
// `idr.match`, and the elements of arrays through one anchor per element
// type, written by `idr.array.new`, `idr.array.set` and `idr.array.generate`
// and read by `idr.array.get` and the body of `idr.array.fold`. The
// framework follows only calls of symbols, so the pass joins the rest
// itself: the entry arguments of a function get the captures of its closures
// and suspensions (`idr.closure` and `idr.suspend` ops and `#idr.closure`
// constants) and the arguments of every `idr.apply` that may call it, an
// `idr.apply` gets the results of every label it may call, and an
// `idr.force` those of every label its cell may hold.
//
// Sums are keyed by (closure or lazy type, label set), not by type alone.
// Every slot that holds a closure or a suspension (a value, a function
// argument or result, a field of a constructor, the elements of arrays) has
// the key of its type and the labels the analysis found for it; a closure,
// suspension or constant used only where one larger set is expected takes
// that set. A closure's key is converted when its labels are known, not
// empty and fit the type. Its values belong to a new sum `@fn$<n>`, unboxed
// unless the key is on a cycle of "a capture of one of its labels holds,
// directly or through unboxed data, a value of key K": only such a cycle
// makes an unboxed sum infinite, and a box ends it, as a recursive set of
// lambdas is a recursive datatype. A closure of type T may capture another
// closure of type T without a cycle when the captured one holds other labels
// (a state monad's bind captures a bind of different lambdas). The sums are
// numbered by first appearance in the module, with one constructor per
// label whose fields are the label's captures, each with the key of that
// capture (the label's entry argument): `idr.closure @f(...)` becomes
// `idr.con @fn$n::@f(...)`, a closure constant the matching constructor
// constant, and `idr.apply` an `idr.match` over the labels the callee may
// hold, each region calling its label.
//
// A lazy key whose labels are known, fit its type and return into one key
// becomes a memo sum `@lazy$<n>`, numbered apart: always a box, since a
// cell has one memo that every reference sees, with a constructor per label
// as a closure sum has, then `running` and `forced`, whose one field is the
// value. `idr.suspend @f(...)` becomes `idr.con @lazy$n::@f(...)`, a
// suspension constant the constructor constant, and `idr.force` takes the
// box; how a force writes the cell is the lowering's. A label whose
// function reaches, through direct calls, an effect a program's outside can
// observe is `by_name`, so that the effect happens at every force where the
// value is demanded, unless a static constant names it: a top-level
// constant is one value of the program, evaluated once.
//
// Where a value flows from a slot into one of another key (call operand to
// argument, return to result, yield to match result, field, element,
// capture, and through a rewritten apply to and from its labels), a
// coercion is inserted: an `idr.match` that rebuilds each label in the other
// sum, and a cell's state, or as an `idr.closure` when the other key stays
// a closure. A value the analysis never reaches (the empty set) becomes
// `ub.poison`. A key stays a closure when a value can reach it only as a
// closure, and then every label that can reach it keeps the closure type's
// signature: its argument and result slots of closure type stay closures
// too. Nothing lowers a closure or a suspension, so a key that stays one,
// unless no value reaches it, is one the analysis could not convert: the
// module is left as it was, and `defunctionalize` names each such key with
// the op where the analysis lost its value.
//
// Then every type is in its runtime shape, and no declaration changes after
// this: a record or closure sum that would make a cell holding it count
// more references than a header can becomes a box, widest first
// (idr.layout's fit). A sum of several user constructors is looked
// through, never boxed, because a field read of it may already run where
// its constructor is not known.
export module idr.defunctionalize:sums;

import idr.mlir;
import idr.layout;

import :analysis;
import :byname;
import :closures;
import :converter;
import :decided;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::defunctionalize {

// What `defunctionalize` made of the module's keys: the sums, the keys that
// stay closures because no value reaches them, and the keys it could not
// convert, which leave the module unchanged; and the declarations it made
// boxes so that the cells holding them fit.
export struct Defunctionalized {
  uint64_t sums = 0;
  uint64_t closures = 0;
  uint64_t boxed = 0;
  SmallVector<UnknownKey> unknown;
};

// Converts every key of `module` into a sum, unless one cannot be. Fails
// when the analysis fails.
export FailureOr<Defunctionalized> defunctionalize(ModuleOp top) {
  Module module(top);
  module.gather();
  DataFlowSolver solver(DataFlowConfig().setInterprocedural(true));
  loadBaselineAnalyses(solver);
  solver.load<LabelAnalysis>(module);
  if (failed(solver.initializeAndRun(top)))
    return failure();
  Converter converter(module, solver);
  converter.decideKeys();
  Defunctionalized done;
  done.unknown = converter.unknownKeys();
  if (!done.unknown.empty())
    return done;
  converter.rewrite();
  markByName(module);
  done.boxed = idr::layout::fit(top);
  done.sums = converter.converted.size();
  done.closures = static_cast<uint64_t>(llvm::count_if(converter.keys, [&](const auto &entry) {
    return isClosureType(entry.first.first) && !converter.isConverted(entry.first);
  }));
  return done;
}

} // namespace idr::defunctionalize
