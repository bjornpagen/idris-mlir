// idr-inline: MLIR's inliner, deciding what to inline as MLton does.
//
// A leaf function, one that calls nothing (an apply calls something), is
// inlined when it has at most kLeafSize ops. Any other function is inlined
// when (calls - 1) * (size - kSmall) <= kProduct: a function under kSmall
// ops always is, a larger one only while its copies stay within kProduct
// ops. Its calls are its call sites and the closures that name it, since
// each closure becomes a call where it is applied. A function on a cycle of
// calls never is: inlining would unroll the cycle; the loop breakers keep
// the cycles through closures no_inline. The decisions are taken once,
// before anything is inlined, from the callees up, a callee that will be
// inlined counting with its size where it is called.

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
        if (!llvm::is_contained(callees[fn], target))
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

  void runOnOperation() override {
    ModuleOp module = getOperation();
    Decisions decisions = decide(module);
    numInlinable += decisions.inlined.size();
    numLeaves += decisions.leaves;

    InlinerConfig config;
    std::string pipeline = defaultPipeline;
    config.setDefaultPipeline([pipeline](OpPassManager &pm) {
      if (!pipeline.empty())
        (void)parsePassPipeline(pipeline, pm);
    });
    unsigned iterations = maxIterations;
    config.setMaxInliningIterations(iterations ? iterations
                                               : std::numeric_limits<unsigned>::max());
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

  void getDependentDialects(DialectRegistry &registry) const override {
    OpPassManager pm(func::FuncOp::getOperationName());
    if (succeeded(parsePassPipeline(defaultPipeline, pm)))
      pm.getDependentDialects(registry);
  }

  // The inliner runs the default pipeline on each function as part of
  // this pass.
  static LogicalResult runPipelineHelper(Pass &pass, OpPassManager &pipeline, Operation *op) {
    return static_cast<Inline &>(pass).runPipeline(pipeline, op);
  }
};

} // namespace
