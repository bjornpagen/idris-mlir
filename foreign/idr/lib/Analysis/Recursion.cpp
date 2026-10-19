// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Which functions may have more than one frame live at a time, from the
// program's cycles of calls.
#include "idr/Analysis/Recursion.h"

#include "idr/IR/Tail.h"

#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr {

Recursion::Recursion(Operation *program, AnalysisManager &am) {
  const CallCycles &cycles = am.getAnalysis<CallCycles>();
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

bool Recursion::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Recursion>() || !pa.isPreserved<CallCycles>();
}

} // namespace idr
