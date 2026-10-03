// breaks-last: a cycle that holds a function that does not break last
// (idr.break_last) never breaks at one that does, unless at a clone, the
// newest of which breaks its cycle whatever it is.
export module idr.expect:breaksLast;

import idr.mlir;
import idr.dialect;
import idr.facts;
import idr.graph;

import :references;
import :report;

using namespace mlir;

namespace idr::expect {

// No cycle that holds a function without idr.break_last breaks at one with
// it, other than at a clone.
//
// A breaker that breaks last, and is no clone, was chosen in a cycle of
// functions that all break last: it is on a cycle of such functions still.
export LogicalResult breaksLast(ModuleOp module, StringRef) {
  SymbolTable symbols(module);
  SmallVector<func::FuncOp> last;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal() && idr::facts::breaksLast(fn))
      last.push_back(fn);
  auto refers = [&](func::FuncOp fn) { return references(symbols, fn); };
  llvm::DenseSet<func::FuncOp> onCycle;
  for (const SmallVector<func::FuncOp> &cycle :
       idr::graph::stronglyConnected<func::FuncOp>(last, refers))
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
