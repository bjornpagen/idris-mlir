// idr.simplify:round: the passes of one round of the simplify loop.
export module idr.simplify:round;

import idr.mlir;

using namespace mlir;

namespace idr::simplify {

// The passes of one round of idr-simplify, as textual pipelines, in order.
//
// The inliner simplifies each function and inlines the calls that exposes
// until an iteration inlines nothing, not a fixed number of times (upstream's
// default is 4): unfolding a sequence of n actions, as a `do` block of n
// statements is (each `>>` applies the closure of the rest), takes n
// iterations, each of which canonicalizes the function, while each round
// runs every pass on the whole module; with a bound, the loop took a round
// for every statement or two, each as long as the program is large. The
// iterations end as the rounds do: every cycle of references keeps a loop
// breaker, and inlining and canonicalization only copy references that
// exist, so no iteration closes a new cycle.
//
// Specialization takes no option: it is finite by construction, and its
// budget is an assertion of its own.
export SmallVector<std::string> simplifyRound(unsigned inlineIterations) {
  return {
      "idr-loop-breakers",
      "idr-effects",
      llvm::formatv("idr-inline{{default-pipeline=idr-canonicalize max-iterations={0}}",
                    inlineIterations),
      "idr-specialize",
      "sccp",
      "int-range-optimizations",
      "idr-canonicalize",
      "cse",
      "idr-eval",
      // remove-dead-values without its own canonicalization, which folds
      // region-branch patterns on the matches alone: a field one of them
      // folds leaves the constructor it read dead but in place, still
      // holding a world or a linear value that the fold's user now holds
      // too. The next round's canonicalization runs on everything and
      // erases what is dead.
      "remove-dead-values{canonicalize=false}",
      "symbol-dce",
  };
}

} // namespace idr::simplify
