// idr-inline: MLIR's inliner, deciding what to inline as MLton does.
//
// A leaf function, one that calls nothing (an apply calls something), is
// inlined when it has at most kLeafSize ops. Any other function is inlined
// when (calls - 1) * (size - kSmall) <= kProduct: a function under kSmall
// ops always is, a larger one only while its copies stay within kProduct
// ops. Its calls are its call sites and the closures that name it, since
// each closure becomes a call where it is applied. A function on a cycle of
// calls never is, since inlining it would unroll the cycle; the cycles are
// those that remain once the loop breakers (no_inline) cut every cycle of
// references, so that the other functions of a loop inline into its breaker
// and its recursion becomes a self call. The decisions are taken once,
// before anything is inlined, from the callees up, a callee that will be
// inlined counting with its size where it is called. A caller that takes in
// a body without Idris's proof of termination loses its own (facts::inlined).

#include "Passes/Scc.h"
#include "idr/Idr.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/Pass/PassManager.h"
#include "mlir/Transforms/Inliner.h"

#include "llvm/ADT/DenseSet.h"

#include <limits>

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRINLINE
#include "idr/Passes.h.inc"
} // namespace idr

import idr.facts;

namespace {

constexpr int64_t kLeafSize = 40;
constexpr int64_t kSmall = 60;
constexpr int64_t kProduct = 320;

struct Decisions {
  llvm::DenseSet<Operation *> inlined;
  unsigned leaves = 0;
};

Decisions decide(ModuleOp module) {
  SymbolTable symbols(module);
  SmallVector<func::FuncOp> functions;
  llvm::DenseMap<func::FuncOp, SmallVector<func::FuncOp>> callees;
  llvm::DenseMap<func::FuncOp, int64_t> calls;
  llvm::DenseSet<func::FuncOp> leaves, selfCalls;
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal())
      continue;
    functions.push_back(fn);
    bool leaf = true;
    fn.getBody().walk([&](Operation *op) {
      if (isa<CallOpInterface>(op))
        leaf = false;
      if (auto call = dyn_cast<func::CallOp>(op)) {
        auto target = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
        if (!target)
          return;
        if (target == fn) {
          selfCalls.insert(fn);
          return;
        }
        ++calls[target];
        if (!target.getNoInline() && !llvm::is_contained(callees[fn], target))
          callees[fn].push_back(target);
        return;
      }
      if (auto closure = dyn_cast<idr::ClosureOp>(op)) {
        if (auto target = symbols.lookup<func::FuncOp>(closure.getCalleeAttr().getAttr()))
          ++calls[target];
        return;
      }
      op->getAttrDictionary().walk([&](idr::ClosureAttr closure) {
        if (auto target = symbols.lookup<func::FuncOp>(closure.getCallee().getAttr()))
          ++calls[target];
      });
    });
    if (leaf)
      leaves.insert(fn);
  }

  Decisions out;
  llvm::DenseMap<func::FuncOp, int64_t> sizes;
  // Tarjan's components come callees first.
  for (const SmallVector<func::FuncOp> &component :
       idr::passes::stronglyConnected<func::FuncOp>(
           functions, [&](func::FuncOp fn) { return callees.lookup(fn); })) {
    if (component.size() != 1)
      continue;
    func::FuncOp fn = component.front();
    if (fn.getNoInline() || selfCalls.contains(fn))
      continue;
    int64_t size = 0;
    fn.getBody().walk([&](Operation *op) {
      ++size;
      if (auto call = dyn_cast<func::CallOp>(op)) {
        auto target = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr());
        if (target && out.inlined.contains(target.getOperation()))
          size += sizes.lookup(target) - 1;
      }
    });
    sizes[fn] = size;
    bool leaf = leaves.contains(fn) && size <= kLeafSize;
    if (leaf || (calls.lookup(fn) - 1) * (size - kSmall) <= kProduct) {
      out.inlined.insert(fn.getOperation());
      out.leaves += leaf;
    }
  }
  return out;
}

struct Inline : idr::impl::IdrInlineBase<Inline> {
  using IdrInlineBase::IdrInlineBase;

  // The default pipeline is parsed once, here, so that a pipeline that does
  // not parse fails the pass instead of running nothing on every function.
  LogicalResult initialize(MLIRContext *ctx) override {
    std::string text = defaultPipeline;
    std::string error;
    llvm::raw_string_ostream os(error);
    OpPassManager parsed;
    if (failed(parsePassPipeline(text, parsed, os)))
      return emitError(UnknownLoc::get(ctx))
             << "idr-inline: the default pipeline \"" << text
             << "\" does not parse: " << StringRef(error).trim();
    pipeline = std::move(parsed);
    return success();
  }

  void runOnOperation() override {
    ModuleOp module = getOperation();
    Decisions decisions = decide(module);
    numInlinable += decisions.inlined.size();
    numLeaves += decisions.leaves;

    InlinerConfig config;
    // The inliner hands a pass manager anchored on the function's op; the
    // parsed pipeline, anchored on any op, runs there.
    config.setDefaultPipeline([this](OpPassManager &pm) { pm = pipeline; });
    unsigned iterations = maxIterations;
    config.setMaxInliningIterations(iterations ? iterations
                                               : std::numeric_limits<unsigned>::max());
    config.setCloneCallback([clone = config.getCloneCallback()](
                                OpBuilder &builder, Region *src, Block *inlineBlock,
                                Block *postInsertBlock, IRMapping &mapper, bool cloned) {
      Operation *at = inlineBlock->getParentOp();
      auto into = isa<func::FuncOp>(at) ? cast<func::FuncOp>(at) : at->getParentOfType<func::FuncOp>();
      if (into)
        idr::facts::inlined(into, dyn_cast<func::FuncOp>(src->getParentOp()));
      clone(builder, src, inlineBlock, postInsertBlock, mapper, cloned);
    });
    auto profitable = [&](const Inliner::ResolvedCall &call) {
      Region *region = call.targetNode->getCallableRegion();
      return region && decisions.inlined.contains(region->getParentOp());
    };
    CallGraph &graph = getAnalysis<CallGraph>();
    Inliner inliner(module, graph, *this, getAnalysisManager(), runPipelineHelper, config,
                    profitable);
    if (failed(inliner.doInlining()))
      signalPassFailure();
  }

  // A pipeline that does not parse loads nothing, and initialize reports
  // it.
  void getDependentDialects(DialectRegistry &registry) const override {
    OpPassManager pm(func::FuncOp::getOperationName());
    if (succeeded(parsePassPipeline(defaultPipeline, pm, llvm::nulls())))
      pm.getDependentDialects(registry);
  }

  // The inliner runs the default pipeline on each function as part of
  // this pass.
  static LogicalResult runPipelineHelper(Pass &pass, OpPassManager &pipeline, Operation *op) {
    return static_cast<Inline &>(pass).runPipeline(pipeline, op);
  }

  OpPassManager pipeline;
};

} // namespace
