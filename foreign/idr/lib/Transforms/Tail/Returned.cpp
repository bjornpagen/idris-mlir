// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- Returned.cpp - Which results are always one of the arguments -------===//
//
// A value threaded through a function and given back (a linear array
// through every read and write of it, the state of a recursion or of a
// loop) is, once lowered, the argument itself on every path: through what
// a region branch joins (an scf.if, a loop whose every iteration yields it
// unchanged, as idr-tail-loops makes of a tail recursion, with poison
// where an exit value has none yet), and through the calls, whose result
// is the operand they pass where their callee returns its argument. The
// result is then no information: the caller holds that value already, live
// across the call.
//
// Which argument a value is is one sparse forward dataflow over the module,
// on upstream's solver: every argument of a function is itself, a region
// branch's values are the join of what flows into them (the base's rule),
// and the solver's optimistic start is the hypothesis a recursion or a loop
// is solved under. Only a private function every use of which is a direct
// call changes its signature. A result that is an argument on some paths
// only stays, and so does one returned only by calls that never return,
// which stays at the bottom.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/Support/Actions.h"

#include "mlir/Analysis/DataFlow/SparseAnalysis.h"
#include "mlir/Analysis/DataFlow/Utils.h"
#include "mlir/Analysis/DataFlowFramework.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"

#include <cassert>

using namespace mlir;

namespace idr::tail {
namespace {

// idr-returned-arguments decides that one function's returned arguments
// drop; the unit is the func.func. The action is the decision: a function
// whose drop it skips keeps its results, and returns its argument all the
// same, so what its callers' results are known to be stays true.
struct ReturnedDropAction : support::TaggedAction<ReturnedDropAction> {
  using TaggedAction::TaggedAction;
  static constexpr llvm::StringLiteral tag = "idr-returned-arguments-drop";
};

using Known = Returned::Known;

struct KnownLattice : dataflow::Lattice<Known> {
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(KnownLattice)
  using Lattice::Lattice;
};

class ReturnedAnalysis : public dataflow::SparseForwardDataFlowAnalysis<KnownLattice> {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(ReturnedAnalysis)
  using SparseForwardDataFlowAnalysis::SparseForwardDataFlowAnalysis;

  // A ub.poison is a value of the program given where nothing reads it (on
  // the path of a loop that does not take it, after a crash): it may be
  // anything, so it stays at the bottom, which agrees with every argument.
  // A select is either of its values. Any other op makes a value of its
  // own, no argument.
  LogicalResult visitOperation(Operation *op, ArrayRef<const KnownLattice *>,
                               ArrayRef<KnownLattice *> results) override {
    if (isa<ub::PoisonOp>(op))
      return success();
    if (auto select = dyn_cast<SelectLikeOpInterface>(op)) {
      ProgramPoint *after = getProgramPointAfter(op);
      KnownLattice *result = results.front();
      join(result, *getLatticeElementFor(after, select.getTrueValue()));
      join(result, *getLatticeElementFor(after, select.getFalseValue()));
      return success();
    }
    setAllToEntryStates(results);
    return success();
  }

  void setToEntryState(KnownLattice *lattice) override {
    propagateIfChanged(lattice, lattice->join(Known::none()));
  }

protected:
  // Argument `i` of a function is its argument `i`, whoever calls it.
  void visitCallableOperation(CallableOpInterface,
                              ArrayRef<dataflow::AbstractSparseLattice *> args) override {
    for (auto [index, arg] : llvm::enumerate(args)) {
      auto *lattice = static_cast<KnownLattice *>(arg);
      propagateIfChanged(lattice, lattice->join(Known::arg(static_cast<unsigned>(index))));
    }
  }

  // A call's result is what its callee's returns give, read in the caller:
  // the callee's argument `a` is the operand the call passes at `a`. A
  // callee whose returns the solver does not all see (a declaration, one
  // called from outside) gives no argument.
  LogicalResult
  visitCallOperation(CallOpInterface call, ArrayRef<const dataflow::AbstractSparseLattice *>,
                     ArrayRef<dataflow::AbstractSparseLattice *> results) override {
    ProgramPoint *after = getProgramPointAfter(call);
    const auto *returns = getOrCreateFor<dataflow::PredecessorState>(after, after);
    if (!returns->allPredecessorsKnown()) {
      dataflow::AbstractSparseForwardDataFlowAnalysis::setAllToEntryStates(results);
      return success();
    }
    for (Operation *ret : returns->getKnownPredecessors())
      for (auto [operand, result] : llvm::zip_equal(ret->getOperands(), results)) {
        const Known &known = getLatticeElementFor(after, operand)->getValue();
        // The callee's own argument is the caller's operand there; the
        // bottom and the top read the same in either function.
        if (std::optional<unsigned> argument = known.argument())
          join(result, *getLatticeElementFor(after, call.getArgOperands()[*argument]));
        else
          propagateIfChanged(result, static_cast<KnownLattice *>(result)->join(known));
      }
    return success();
  }
};

} // namespace

void Returned::Known::print(raw_ostream &os) const {
  if (std::optional<unsigned> index = argument())
    os << "argument " << *index;
  else if (std::holds_alternative<NoOne>(state))
    os << "no one argument";
  else
    os << "unconstrained";
}

SmallVector<unsigned> Returned::Function::kept() const {
  SmallVector<unsigned> kept;
  for (auto [i, result] : llvm::enumerate(results))
    if (!result.known.argument())
      kept.push_back(static_cast<unsigned>(i));
  return kept;
}

const Returned::Function *Returned::dropping(StringAttr name) const {
  auto it = functions.find(name);
  return it != functions.end() ? &it->second : nullptr;
}

Returned::Returned(Operation *module, AnalysisManager &) {
  DataFlowSolver solver;
  dataflow::loadBaselineAnalyses(solver);
  solver.load<ReturnedAnalysis>();
  // The lattice is of finite height over the module's values, so the solve
  // ends, and no visit of it fails.
  [[maybe_unused]] LogicalResult solved = solver.initializeAndRun(module);
  assert(succeeded(solved) && "the returned-arguments solve does not fail");

  // Eligible: every use is a direct call, so the calls are all the users.
  SymbolTableCollection tables;
  SymbolUserMap users(tables, module);
  for (auto fn : cast<ModuleOp>(module).getOps<func::FuncOp>()) {
    if (fn.isExternal() || fn.isPublic() || fn.getNumResults() == 0)
      continue;
    ArrayRef<Operation *> calls = users.getUsers(fn);
    if (!llvm::all_of(calls, [](Operation *user) { return isa<func::CallOp>(user); }))
      continue;
    // A result is what every return gives; a value the solver never reached
    // is on no path that runs.
    Function function;
    for (Type type : fn.getResultTypes())
      function.results.push_back({type, Known()});
    fn.walk([&](func::ReturnOp ret) {
      for (auto [result, operand] : llvm::zip_equal(function.results, ret.getOperands()))
        if (const auto *lattice = solver.lookupState<KnownLattice>(operand))
          result.known = Known::join(result.known, lattice->getValue());
    });
    if (llvm::none_of(function.results,
                      [](const Result &result) { return result.known.argument().has_value(); }))
      continue;
    (void)support::perform<ReturnedDropAction>(fn, [&] {
      numDropped += static_cast<unsigned>(function.results.size() - function.kept().size());
      changed.insert(fn.getSymNameAttr());
      for (Operation *call : calls)
        if (auto caller = call->getParentOfType<func::FuncOp>())
          changed.insert(caller.getSymNameAttr());
      functions[fn.getSymNameAttr()] = std::move(function);
    });
  }
}

} // namespace idr::tail
