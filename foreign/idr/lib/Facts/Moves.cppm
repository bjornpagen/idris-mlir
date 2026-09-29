// idr.facts:moves: which code may be dropped, delayed or moved, from what
// its ops may do.
export module idr.facts:moves;

import idr.mlir;

import :effects;

export namespace idr::facts {

// Whether `op` only computes: nothing in it performs IO, crashes or may
// not return, and every call in it is of a function that does none of
// these, given closures that do none of these. It may then move across any
// op, and any op across it, run on fewer paths, or not at all.
bool canMoveAcross(mlir::Operation *op);

// Whether `op` may run later, past ops that only compute, as long as it
// still runs on every path it runs on now: nothing in it performs IO, but
// it may crash or not return, since nothing that could observe the
// difference comes between.
bool canDelay(mlir::Operation *op);

// Whether `call`, whose results are unused, may go: it only computes.
bool canDrop(mlir::func::CallOp call);

} // namespace idr::facts

// Not exported: the units of idr.facts share it, importers never see it.
namespace idr::facts {

// Whether every op in `op`, itself included, does only what `allowed`
// accepts.
bool only(mlir::Operation *op, llvm::function_ref<bool(const Effects &)> allowed);

} // namespace idr::facts
