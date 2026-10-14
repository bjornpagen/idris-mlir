// idris-mlir's pipeline, from the idr dialect to the LLVM dialect, written
// once as a sequence of constructor calls. What builds it and what lists
// the names --without may give both read that one sequence, so no list of
// names exists beside it.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Canonicalize.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Conversion/Passes.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/Dialect/Linalg/Passes.h"
#include "mlir/Dialect/MemRef/Transforms/Passes.h"
#include "mlir/Pass/Pass.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Pass/PassRegistry.h"
#include "mlir/Transforms/Passes.h"

#include "llvm/ADT/StringRef.h"

#include <memory>
#include <string>
#include <vector>

namespace {

// Where the sequence goes: a pass on the module (top), the start of a
// group of passes run on every operation of one kind directly inside the
// module (group), and a pass of the group last started (nested). A top
// pass ends the group.
class Sink {
public:
  virtual ~Sink() = default;
  virtual void top(std::unique_ptr<mlir::Pass> pass) = 0;
  virtual void group(llvm::StringRef anchor) = 0;
  virtual void nested(std::unique_ptr<mlir::Pass> pass) = 0;
};

// Into a manager, leaving out what the options leave out. A group's manager
// is made at its first pass that stays, so a group whose passes are all
// left out has none, and one with a pass left out keeps its other passes
// under the one manager, which MLIR runs over the functions in parallel.
class Build final : public Sink {
public:
  Build(mlir::OpPassManager &pm, const idr::PipelineOptions &options) : pm(pm), options(options) {}

  void top(std::unique_ptr<mlir::Pass> pass) override {
    anchor = {};
    open = nullptr;
    if (!options.without.contains(pass->getArgument()))
      pm.addPass(std::move(pass));
  }

  void group(llvm::StringRef name) override {
    anchor = name;
    open = nullptr;
  }

  void nested(std::unique_ptr<mlir::Pass> pass) override {
    if (options.without.contains(pass->getArgument()))
      return;
    if (!open)
      open = &pm.nest(anchor);
    open->addPass(std::move(pass));
  }

private:
  mlir::OpPassManager &pm;
  const idr::PipelineOptions &options;
  llvm::StringRef anchor;
  mlir::OpPassManager *open = nullptr;
};

// The argument of every pass, in order.
class Names final : public Sink {
public:
  explicit Names(std::vector<std::string> &names) : names(names) {}

  void top(std::unique_ptr<mlir::Pass> pass) override { names.push_back(pass->getArgument().str()); }
  void group(llvm::StringRef) override {}
  void nested(std::unique_ptr<mlir::Pass> pass) override {
    names.push_back(pass->getArgument().str());
  }

private:
  std::vector<std::string> &names;
};

// The pipeline. LLVM's own pipeline runs in idris-mlir, after it.
void pipeline(Sink &sink, const idr::PipelineOptions &options) {
  llvm::StringRef functions = idr::FuncOp::getOperationName();
  llvm::StringRef lowered = mlir::func::FuncOp::getOperationName();
  // First: every closure and suspension Emit wrote as a region becomes a
  // function of its own, its captures leading, so that every later pass
  // sees the symbol form.
  sink.top(idr::createIdrIsolate());
  // Before the simplify loop, while each case block still has the one call
  // its parent makes: case-of-case would copy that call.
  sink.top(idr::createIdrContify());
  sink.top(idr::createIdrSimplify());
  sink.top(idr::createIdrDefunctionalize());
  sink.group(functions);
  sink.nested(idr::createCanonicalizerPass());
  // A cell that never leaves its frame goes on the stack before counting,
  // which reuses only the cells of the heap. Counting runs on functional
  // code, where recursion is still a call and a match's yield is its join
  // point; every later pass keeps its rule.
  sink.top(idr::createIdrStack());
  // While a self call's result is still the operand of the addition a tail
  // returns. Counting borrows that result and drops it after the addition,
  // and the call would no longer be the tail.
  sink.top(idr::createIdrAccumulate());
  sink.top(idr::createIdrRc(idr::IdrRcOptions{.reuse = !options.without.contains("reuse"),
                                              .sink = !options.without.contains("sink")}));
  // On the grades counting wrote: a promise the program was asked to keep,
  // and nothing unless it was asked.
  sink.top(idr::createIdrDemand(idr::IdrDemandOptions{
      .inPlace = options.demandInPlace && !options.without.contains("in-place")}));
  sink.top(idr::createIdrTrmc());
  sink.group(functions);
  sink.nested(idr::createIdrTailLoops());
  // On loops, which it versions, and after counting, whose counts of the
  // bigs it proves small it removes.
  sink.top(idr::createIdrNarrow());
  // On the loops and words idr-narrow leaves, where its index systems see
  // the most.
  sink.top(idr::createIdrInBounds());
  sink.top(idr::createIdrLower());
  // The lowered root becomes the program's entry, @main.
  sink.top(idr::createIdrEntry());
  // The loops over arrays are linalg ops after lowering: each with a
  // parallel dimension is tiled by the target's lanes and vectorized, and
  // upstream makes the loops of those left. On the vectorized loops, the
  // integer lanes of each compute in 32 bits under a bound on the sizes,
  // the 64-bit loop kept for the sizes above it.
  sink.group(lowered);
  sink.nested(idr::createIdrVectorize());
  sink.nested(idr::createIdrNarrowLanes());
  sink.nested(mlir::createConvertLinalgToLoopsPass());
  sink.nested(idr::createCanonicalizerPass());
  sink.nested(mlir::createCSEPass());
  // On lowered code, where a threaded value given back is its argument
  // component by component; a join that then yields the same value on
  // every path folds after it.
  sink.top(idr::createIdrReturnedArguments());
  // The tiles' transfers of a rank above one become loops over 1-D ones;
  // the views become offsets, the offset of a view of a view the affine
  // arithmetic of both, before the affine ops lower with the loops' bounds.
  // Each of these reads one function, so they run over the functions in
  // parallel.
  sink.group(lowered);
  sink.nested(idr::createCanonicalizerPass());
  sink.nested(mlir::createCSEPass());
  sink.nested(mlir::createConvertVectorToSCFPass());
  sink.nested(mlir::memref::createExpandStridedMetadataPass());
  sink.nested(mlir::createLowerAffinePass());
  sink.nested(mlir::createSCFToControlFlowPass());
  // The vector ops then take the vector dialect's own conversion, whose
  // pre-lowering (transfers to loads and stores, steps, broadcasts, shape
  // casts) convert-to-llvm does not carry.
  sink.top(mlir::createConvertVectorToLLVMPass());
  sink.top(mlir::createConvertToLLVMPass());
  sink.top(mlir::createReconcileUnrealizedCastsPass());
  // On the final control flow, where a call's path to the return is what
  // LLVM sees.
  sink.top(idr::createIdrTailCalls());
}

} // namespace

void idr::buildPipeline(mlir::OpPassManager &pm, const PipelineOptions &options) {
  Build build(pm, options);
  pipeline(build, options);
}

std::vector<std::string> idr::pipelinePassNames() {
  std::vector<std::string> names;
  Names lister(names);
  pipeline(lister, PipelineOptions{});
  return names;
}

void idr::registerIdrPipeline() {
  mlir::PassPipelineRegistration<>(
      "idr-pipeline", "idris-mlir's pipeline, the idr dialect to the LLVM dialect",
      [](mlir::OpPassManager &pm) { buildPipeline(pm, PipelineOptions{}); });
}
