// idr.facts:breakslast: `idr.break_last`.
export module idr.facts:breakslast;

import idr.mlir;

using namespace mlir;

export namespace idr::facts {

// Whether a cycle of references breaks at `fn` only when it has no function
// that does not (`idr.break_last`, the registry's column).
bool breaksLast(func::FuncOp fn) { return fn->hasAttr("idr.break_last"); }

} // namespace idr::facts
