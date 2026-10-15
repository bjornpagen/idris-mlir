// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where a frame runs again, for the escape analysis: which functions share
// a cycle of calls (its tail rule, and the frame budget), the strongly
// connected components of the program's call graph, the one every pass
// reads; and which loops run a con again in its frame. Then the answers,
// read off the solve (Escapes.cpp) beside the loops.
#include "idr/Analysis/EscapesDetail.h"

#include "idr/Analysis/Tail.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/IR/Threading.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/LoopLikeInterface.h"
#include "llvm/ADT/SCCIterator.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr {

void Escapes::findCycles(AnalysisManager &am) {
  const CallGraph &graph = am.getAnalysis<CallGraph>();
  // A component of several functions is a cycle. A function alone is on
  // one when it calls itself other than in tail position: idr-tail-loops
  // makes a self call there the next iteration of a loop in the same frame.
  SmallVector<Operation *> alone;
  unsigned number = 0;
  for (auto scc = llvm::scc_begin(&graph); !scc.isAtEnd(); ++scc, ++number) {
    SmallVector<Operation *, 4> members;
    for (const CallGraphNode *node : *scc)
      if (!node->isExternal())
        members.push_back(node->getCallableRegion()->getParentOp());
    for (Operation *fn : members)
      component[fn] = number;
    if (members.size() > 1)
      onCycle.insert(members.begin(), members.end());
    else if (members.size() == 1 && scc.hasCycle())
      alone.push_back(members.front());
  }
  // Each function's own body, in parallel: a walk of it and nothing more.
  SmallVector<char> again(alone.size(), 0);
  parallelFor(program->getContext(), 0, alone.size(),
              [&](size_t at) {
                auto fn = cast<FuncOp>(alone[at]);
                again[at] = fn.walk([&](CallOp call) {
                                if (call.getCalleeAttr().getAttr() == fn.getSymNameAttr() &&
                                    !tail::inTailPosition(call))
                                  return WalkResult::interrupt();
                                return WalkResult::advance();
                              })
                                .wasInterrupted();
              });
  for (auto [fn, recurs] : llvm::zip_equal(alone, again))
    if (recurs)
      onCycle.insert(fn);
}

bool Escapes::recursive(FuncOp fn) const { return onCycle.contains(fn.getOperation()); }

// The regions a con may be in are those whose runs this analysis knows: a
// region branch's, whose interface says which regions run again (a loop's
// body) and which at most once (a match's case), and whose runs never
// overlap, as they do in a region the op holds as parallel
// (HasParallelRegion). The walk goes up the regions around the con, which
// nest finitely, to its function's body.
std::optional<SmallVector<Operation *, 2>> Escapes::loopsAround(ConOp con) const {
  SmallVector<Operation *, 2> loops;
  for (Region *region = con->getParentRegion(); region;
       region = region->getParentOp()->getParentRegion()) {
    if (!region->hasOneBlock())
      return std::nullopt;
    Operation *parent = region->getParentOp();
    if (isa<FuncOp>(parent) && parent->getParentOp() == program)
      return loops;
    auto branch = dyn_cast<RegionBranchOpInterface>(parent);
    if (!branch || parent->hasTrait<OpTrait::HasParallelRegion>())
      return std::nullopt;
    if (branch.isRepetitiveRegion(region->getRegionNumber()))
      loops.push_back(parent);
  }
  return std::nullopt;
}

using namespace detail::escapes;

bool Escapes::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Escapes>() || !pa.isPreserved<SymbolTable>();
}

bool Escapes::mayEscape(ConOp con) const {
  std::optional<SmallVector<Operation *, 2>> loops = loopsAround(con);
  if (!loops)
    return true;
  Value cell = con.getResult();
  const EscapeLattice *state = solver.lookupState<EscapeLattice>(cell);
  if (!state)
    return true;
  const Reach &self = part(cell, state->getValue(), Mode::Shallow);
  auto around = [&](Operation *loop) { return llvm::is_contained(*loops, loop); };
  return self.escapes || self.tailCalled || llvm::any_of(self.loops, around);
}

} // namespace idr
