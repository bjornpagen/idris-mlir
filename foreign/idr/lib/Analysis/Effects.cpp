// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What each function's run may do, from what its body does itself and what
// it calls. Over the components of the call graph, callees first, the least
// fixpoint is one pass: a component's effects are the or of its members'
// own parts and of the effects of each callee outside it, final already,
// and every member gets them, and every call of a member with it.
#include "idr/Analysis/Effects.h"

#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Worklist.h"

#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"

#include <cassert>
#include <optional>

using namespace mlir;

namespace {

idr::FuncOp calleeOf(idr::CallOp call, const SymbolTable &symbols) {
  auto callee = symbols.lookup<idr::FuncOp>(call.getCalleeAttr().getAttr());
  assert(callee && "the closed world makes every callee an idr.func of the program");
  return callee;
}

} // namespace

// Each component's effects are written, the function's and every call's,
// before the next component reads them: a caller's component comes later.
void idr::solveEffects(ProgramOp program, const CallCycles &cycles) {
  SymbolTableCollection tables;
  const SymbolTable &symbols = tables.getSymbolTable(program);
  SymbolUserMap users(tables, program);
  for (const CallCycles::Component &component : cycles.components()) {
    SmallVector<FuncOp> members =
        llvm::map_to_vector(component, [](Operation *member) { return cast<FuncOp>(member); });
    Effect sum = componentEffects(members, symbols);
    for (FuncOp member : members)
      writeEffects(member, sum, users);
  }
}

llvm::DenseSet<idr::FuncOp> idr::observableRuns(ProgramOp program, const SymbolTable &symbols,
                                                LabelsRun labelsRun) {
  SmallVector<FuncOp> fns(program.getOps<FuncOp>());
  llvm::DenseMap<Operation *, unsigned> positions;
  for (auto [at, fn] : llvm::enumerate(fns))
    positions.try_emplace(fn.getOperation(), static_cast<unsigned>(at));

  // Each body into its own slot: whether it observes something itself, and
  // what it runs.
  struct Runs {
    bool observes = false;
    SmallVector<FuncOp> targets;
  };
  SmallVector<Runs> runs(fns.size());
  parallelFor(program.getContext(), 0, fns.size(), [&](size_t at) {
    Runs &slot = runs[at];
    fns[at].getBody().walk([&](Operation *op) {
      if (op->hasTrait<ObservableIO>())
        slot.observes = true;
      if (auto call = dyn_cast<CallOp>(op))
        slot.targets.push_back(calleeOf(call, symbols));
      else if (auto runner = dyn_cast<RunsLabelsOpInterface>(op))
        labelsRun(runner, slot.targets);
    });
  });

  // The reach runs backwards, from what observes to what runs it. Each
  // target is a function of the program, so it has a position: a callee is
  // what the program's table resolves, and a label the function the table
  // gives for a label the solve read off the program.
  SmallVector<SmallVector<unsigned>> runners(fns.size());
  for (auto [at, slot] : llvm::enumerate(runs))
    for (FuncOp target : slot.targets)
      runners[positions.at(target.getOperation())].push_back(static_cast<unsigned>(at));
  // Each function enters the worklist once, when it is first found to
  // observe, and joins the set when it leaves it.
  OnceWorklist<unsigned> work;
  for (auto [at, slot] : llvm::enumerate(runs))
    if (slot.observes)
      work.push(static_cast<unsigned>(at));
  llvm::DenseSet<FuncOp> observed;
  while (std::optional<unsigned> at = work.pop()) {
    observed.insert(fns[*at]);
    for (unsigned runner : runners[*at])
      work.push(runner);
  }
  return observed;
}
