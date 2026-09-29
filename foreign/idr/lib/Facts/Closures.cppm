// idr.facts:closures: the closures a value may hold, and what running them
// may do.
export module idr.facts:closures;

import idr.mlir;

import :effects;

export namespace idr::facts {

// The label that `ctor` names when it builds a closure: a constructor of a
// sum of closures (an `idr.data ... closures`), named after its label's
// function. Null for any other constructor.
mlir::StringAttr closureLabel(mlir::Operation *from, mlir::SymbolRefAttr ctor);

// Whether a value of `type` may hold a closure: a closure, a sum of
// closures that idr-defunctionalize made, or data with a field that may; a
// linear value holds what its value does.
bool mayHoldClosure(mlir::Operation *from, mlir::Type type);

// What code given `value` may do by applying the closures it holds: what
// their labels do, through captures and fields. A closure whose label is
// not known where `value` is made may do anything.
Effects passed(mlir::Operation *from, mlir::Value value);

} // namespace idr::facts
