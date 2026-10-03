// Registration of the idr dialect, passes and pipeline.

#include "idr/Idr.h"

#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"

using namespace mlir;

void idr::registerIdr(DialectRegistry &registry) {
  registry.insert<IdrDialect>();
  registerCallEffects(registry);
}

// The pipeline's steps, in order. LLVM's own pipeline runs in idris-mlir-cc.
ArrayRef<StringRef> idr::pipelineSteps() {
  static const StringRef steps[] = {
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
      "idr-rc",
      "idr-trmc",
      "idr-tail-loops",
      // On loops, which it versions, and after counting, whose counts of
      // the bigs it proves small it removes.
      "idr-narrow",
      "idr-lower",
      // The loops over arrays are linalg ops after lowering: each with a
      // parallel dimension is tiled by the target's lanes and vectorized,
      // and upstream makes the loops of those left.
      "idr-vectorize",
      "convert-linalg-to-loops",
      "canonicalize,cse",
      // On lowered code, where a threaded value given back is its argument
      // component by component; a join that then yields the same value on
      // every path folds after it.
      "idr-returned-arguments",
      "canonicalize,cse",
      // The tiles' transfers of a rank above one become loops over 1-D
      // ones, their bounds arithmetic, their views offsets; the vector ops
      // then take the vector dialect's own conversion, whose pre-lowering
      // (transfers to loads and stores, steps, broadcasts, shape casts)
      // convert-to-llvm does not carry.
      "convert-vector-to-scf,lower-affine,expand-strided-metadata,convert-scf-to-cf,"
      "convert-vector-to-llvm,convert-to-llvm,reconcile-unrealized-casts",
      // On the final control flow, where a call's path to the return is
      // what LLVM sees.
      "idr-tail-calls",
  };
  return steps;
}

void idr::registerIdrPipeline() {
  registerIdrPasses();
  PassPipelineRegistration<>(
      "idr-pipeline", "The contract text to the LLVM dialect",
      [](OpPassManager &pm) {
        for (StringRef step : pipelineSteps())
          if (failed(parsePassPipeline(step, pm)))
            llvm::report_fatal_error("idr-pipeline: bad step");
      });
}
