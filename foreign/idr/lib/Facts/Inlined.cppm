// idr.facts:inlined: the facts of a function whose body takes in another's.
export module idr.facts:inlined;

import idr.mlir;

using namespace mlir;

export namespace idr::facts {

// `into`'s body has taken in a copy of `callee`'s (a null callee, one not
// known, has any body). `idr.total` says that every loop of a body is one
// Idris proved terminating; a body that takes in one without that proof
// loses it, since a loop of the callee's may close in it.
void inlined(func::FuncOp into, func::FuncOp callee) {
  if (!callee || !callee->hasAttr("idr.total"))
    into->removeAttr("idr.total");
}

} // namespace idr::facts
