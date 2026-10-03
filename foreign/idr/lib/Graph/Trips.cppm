// idr.graph:trips: how often a loop runs, as upstream's value bounds see its
// bounds: for idr-narrow-lanes, which versions no loop that runs at most
// once, and for the property that states what it versions (Expect/Loops.cc).
export module idr.graph:trips;

import idr.mlir;

export namespace idr::graph {

// Whether `loop` runs at most once: its upper bound exceeds its lower bound
// by less than a step, as for the loop of a peeled tile loop's last tile,
// whose bounds are `n - n mod step` and `n`.
bool runsAtMostOnce(mlir::scf::ForOp loop);

} // namespace idr::graph
