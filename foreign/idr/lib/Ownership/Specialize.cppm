// idr.ownership:specialize: a function specialized on the grade of its
// callers' values. Nothing here is exported: inferExclusive runs it.
module;
#include "llvm/Support/Debug.h"

#define DEBUG_TYPE "idr-rc"

export module idr.ownership:specialize;

import idr.mlir;

import :cells;
import :followed;

using namespace mlir;
using namespace mlir::dataflow;

namespace idr::ownership {

// A function called with exclusive values from some callers and shared ones
// from others would take its parameters shared, and test every cell for
// all of them. Instead it is specialized on the grade, as the specializer
// specializes on types: the calls whose every followed argument is
// exclusive go to a copy of their own, whose parameters the next solve
// proves exclusive. A call is redirected at most once, so the rounds end.
// A function whose callers the solver does not all see (a closure's code)
// keeps them, and a copy is never copied again.
class Specialize {
public:
  // The copies made so far, by their original, which a call made exclusive
  // by an earlier round's copy joins.
  using Copies = llvm::DenseMap<Operation *, func::FuncOp>;

  Specialize(ModuleOp module, DataFlowSolver &solver, Copies &copies)
      : module(module), solver(solver), copies(copies) {}

  bool run() {
    SymbolTableCollection symbols;
    SmallVector<func::FuncOp> fns(module.getOps<func::FuncOp>());
    bool redirected = false;
    for (func::FuncOp fn : fns) {
      if (fn.isExternal() || fn.isPublic() || fn.getSymName().ends_with(copySuffix))
        continue;
      auto *callers = solver.lookupState<PredecessorState>(solver.getProgramPointAfter(fn));
      if (!callers || !callers->allPredecessorsKnown())
        continue;
      SmallVector<func::CallOp> exclusiveCalls;
      bool mixed = false;
      for (Operation *pred : callers->getKnownPredecessors()) {
        auto call = dyn_cast<func::CallOp>(pred);
        if (!call || !isLive(call))
          continue;
        if (improves(fn, call))
          exclusiveCalls.push_back(call);
        else
          mixed = true;
      }
      if (exclusiveCalls.empty() || !mixed)
        continue;
      func::FuncOp copy = copyOf(fn);
      for (func::CallOp call : exclusiveCalls)
        call.setCalleeAttr(FlatSymbolRefAttr::get(copy.getSymNameAttr()));
      LLVM_DEBUG(llvm::dbgs() << "idr-rc: " << exclusiveCalls.size() << " calls of @"
                              << fn.getSymName() << " go to @" << copy.getSymName() << "\n");
      redirected = true;
    }
    return redirected;
  }

private:
  static constexpr StringLiteral copySuffix = "$excl";

  bool isLive(Operation *op) {
    auto *state = solver.lookupState<Executable>(solver.getProgramPointBefore(op->getBlock()));
    return state && state->isLive();
  }

  Sharing sharingOf(Value value) {
    auto *lattice = solver.lookupState<CellsLattice>(value);
    return lattice ? lattice->getValue().sharing : Sharing::Unknown;
  }

  // Whether the call gives every followed parameter an exclusive value, and
  // at least one of them a value the function now takes shared.
  bool improves(func::FuncOp fn, func::CallOp call) {
    bool gains = false;
    for (auto [param, arg] : llvm::zip(fn.getArguments(), call.getArgOperands())) {
      if (!followed(param))
        continue;
      if (sharingOf(arg) != Sharing::Exclusive)
        return false;
      gains |= sharingOf(param) == Sharing::Shared;
    }
    return gains;
  }

  func::FuncOp copyOf(func::FuncOp fn) {
    auto it = copies.find(fn);
    if (it != copies.end())
      return it->second;
    func::FuncOp copy = fn.clone();
    copy.setSymName((fn.getSymName() + copySuffix).str());
    copy.setPrivate();
    OpBuilder b(fn);
    b.setInsertionPointAfter(fn);
    b.insert(copy.getOperation());
    copies.try_emplace(fn, copy);
    return copy;
  }

  ModuleOp module;
  DataFlowSolver &solver;
  Copies &copies;
};

} // namespace idr::ownership
