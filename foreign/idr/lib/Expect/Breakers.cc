// every-cycle-has-breaker: inlining ends because every cycle of references
// among the functions it may inline is cut by a loop breaker (no_inline).
// Which function of a cycle breaks it is the passes' choice; that one
// does is the property.
//
// breaks-last: a cycle that holds a function that does not break last
// (idr.break_last) never breaks at one that does, unless at a clone, the
// newest of which breaks its cycle whatever it is.

#include "Expect/Expect.h"
#include "Passes/Scc.h"

#include "llvm/ADT/DenseSet.h"

import idr.facts;

using namespace mlir;

namespace idr::expect {

namespace {

// A function refers to what it calls and to the functions its closures and
// closure constants name.
SmallVector<func::FuncOp> references(SymbolTable &symbols, func::FuncOp fn) {
  SmallVector<func::FuncOp> out;
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&fn.getBody()))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (auto target = symbols.lookup<func::FuncOp>(use.getSymbolRef().getRootReference()))
        out.push_back(target);
  return out;
}

} // namespace

LogicalResult everyCycleHasBreaker(ModuleOp module, StringRef) {
  SymbolTable symbols(module);
  auto refers = [&](func::FuncOp fn) { return references(symbols, fn); };
  SmallVector<func::FuncOp> inlinable;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal() && !fn.getNoInline())
      inlinable.push_back(fn);
  bool held = true;
  for (const SmallVector<func::FuncOp> &cycle :
       idr::passes::stronglyConnected<func::FuncOp>(inlinable, refers)) {
    if (cycle.size() == 1 && !llvm::is_contained(refers(cycle.front()), cycle.front()))
      continue;
    func::FuncOp first = cycle.front();
    InFlightDiagnostic error = fail(first.getLoc(), "every-cycle-has-breaker")
                               << "no loop breaker in the cycle of";
    for (func::FuncOp fn : cycle)
      error << " @" << fn.getSymName();
    held = false;
  }
  return success(held);
}

// A breaker that breaks last, and is no clone, was chosen in a cycle of
// functions that all break last: it is on a cycle of such functions still.
LogicalResult breaksLast(ModuleOp module, StringRef) {
  SymbolTable symbols(module);
  SmallVector<func::FuncOp> last;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal() && idr::facts::breaksLast(fn))
      last.push_back(fn);
  auto refers = [&](func::FuncOp fn) { return references(symbols, fn); };
  llvm::DenseSet<func::FuncOp> onCycle;
  for (const SmallVector<func::FuncOp> &cycle :
       idr::passes::stronglyConnected<func::FuncOp>(last, refers))
    if (cycle.size() > 1 || llvm::is_contained(refers(cycle.front()), cycle.front()))
      onCycle.insert(cycle.begin(), cycle.end());
  bool held = true;
  for (func::FuncOp fn : last) {
    if (!fn.getNoInline() || fn->hasAttr("idr.clone") || onCycle.contains(fn))
      continue;
    fail(fn.getLoc(), "breaks-last")
        << "@" << fn.getSymName()
        << " breaks last, and breaks a cycle that holds a function that does not";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
