// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where a frame runs again, for the escape analysis: which functions may
// have more than one frame live at a time, from the program's cycles of
// calls (the frame budget); and which loops run a cell op again in its
// frame. Then the answers, read off the solve (Escapes.cpp) beside the
// loops.
#include "idr/Analysis/EscapesDetail.h"

#include "idr/Analysis/CallCycles.h"
#include "idr/Analysis/Tail.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Threading.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "mlir/Interfaces/LoopLikeInterface.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr {

void Escapes::findCycles(const CallCycles &cycles) {
  // A component of several functions is a cycle. A function alone is on
  // one when it calls itself other than in tail position: idr-tail-loops
  // makes a self call there the next iteration of a loop in the same frame.
  SmallVector<Operation *> alone;
  for (const CallCycles::Component &component : cycles.components()) {
    if (component.size() > 1)
      onCycle.insert(component.begin(), component.end());
    else if (cycles.callsItself(component.front()))
      alone.push_back(component.front());
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

// The regions a cell op may be in are those whose runs this analysis
// knows: a region branch's, whose interface says which regions run again
// (a loop's body) and which at most once (a match's case), and whose runs
// never overlap, as they do in a region the op holds as parallel
// (HasParallelRegion). A region branch's region may hold several blocks; a
// function's body is one by its type. The walk goes up the regions around
// the op, which nest finitely, to its function's body.
std::optional<SmallVector<Operation *, 2>> Escapes::loopsAround(Operation *op) const {
  SmallVector<Operation *, 2> loops;
  for (Region *region = op->getParentRegion(); region;
       region = region->getParentOp()->getParentRegion()) {
    Operation *parent = region->getParentOp();
    if (isa<FuncOp>(parent) && parent->getParentOp() == program)
      return loops;
    auto branch = dyn_cast<RegionBranchOpInterface>(parent);
    if (!branch || !region->hasOneBlock() || parent->hasTrait<OpTrait::HasParallelRegion>())
      return std::nullopt;
    if (branch.isRepetitiveRegion(region->getRegionNumber()))
      loops.push_back(parent);
  }
  return std::nullopt;
}

using namespace detail::escapes;

bool Escapes::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Escapes>() || !pa.isPreserved<CallCycles>();
}

bool Escapes::mayEscape(CellNewOp cell) const {
  std::optional<SmallVector<Operation *, 2>> loops = loopsAround(cell);
  if (!loops)
    return true;
  // A cell no use reaches has no state in the solve: it holds the least
  // solution's bottom, which reaches nowhere.
  static const Escape bottom;
  Value made = cell.getCell();
  const EscapeLattice *lattice = solver.lookupState<EscapeLattice>(made);
  const Reach &self = own(made, lattice ? lattice->getValue() : bottom);
  auto around = [&](Operation *loop) { return llvm::is_contained(*loops, loop); };
  return self.escapes || self.tailCalled || llvm::any_of(self.loops, around);
}

} // namespace idr
