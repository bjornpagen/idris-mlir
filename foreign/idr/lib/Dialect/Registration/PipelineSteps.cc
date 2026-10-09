// The steps of idr-pipeline.

#include "idr/Idr.h"

using namespace mlir;

// The pipeline's steps, in order. LLVM's own pipeline runs in idris-mlir-cc.
ArrayRef<StringRef> idr::pipelineSteps() {
  static const StringRef steps[] = {
      // First: every closure and suspension Emit wrote as a region becomes
      // a function of its own, its captures leading, so that every later
      // step sees the symbol form.
      "idr-isolate",
      // Before the simplify loop, while each case block still has the one
      // call its parent makes: case-of-case would copy that call.
      "idr-contify",
      "idr-simplify",
      "idr-defunctionalize",
      "canonicalize",
      // A cell that never leaves its frame goes on the stack before
      // counting, which reuses only the cells of the heap. Counting runs on
      // functional code, where recursion is still a call and a match's
      // yield is its join point; every later step keeps its rule.
      "idr-stack",
      // While a self call's result is still the operand of the addition a
      // tail returns. Counting borrows that result and drops it after the
      // addition, and the call would no longer be the tail.
      "idr-accumulate",
      "idr-rc",
      // On the grades counting wrote: a promise the program was asked to
      // keep, and nothing unless it was asked.
      "idr-demand",
      "idr-trmc",
      "idr-tail-loops",
      // On loops, which it versions, and after counting, whose counts of
      // the bigs it proves small it removes.
      "idr-narrow",
      // On the loops and words idr-narrow leaves, where its index systems
      // see the most.
      "idr-in-bounds",
      "idr-lower",
      // The lowered root becomes the program's entry, @main.
      "idr-entry",
      // The loops over arrays are linalg ops after lowering: each with a
      // parallel dimension is tiled by the target's lanes and vectorized,
      // and upstream makes the loops of those left.
      "idr-vectorize",
      // On the vectorized loops: the integer lanes of each compute in 32
      // bits under a bound on the sizes, the 64-bit loop kept for the
      // sizes above it.
      "idr-narrow-lanes",
      "convert-linalg-to-loops",
      "canonicalize,cse",
      // On lowered code, where a threaded value given back is its argument
      // component by component; a join that then yields the same value on
      // every path folds after it.
      "idr-returned-arguments",
      "canonicalize,cse",
      // The tiles' transfers of a rank above one become loops over 1-D
      // ones; the views become offsets, the offset of a view of a view
      // the affine arithmetic of both, before the affine ops lower with
      // the loops' bounds; the vector ops then take the vector dialect's
      // own conversion, whose pre-lowering (transfers to loads and stores,
      // steps, broadcasts, shape casts) convert-to-llvm does not carry.
      "convert-vector-to-scf,expand-strided-metadata,lower-affine,convert-scf-to-cf,"
      "convert-vector-to-llvm,convert-to-llvm,reconcile-unrealized-casts",
      // On the final control flow, where a call's path to the return is
      // what LLVM sees.
      "idr-tail-calls",
  };
  return steps;
}
