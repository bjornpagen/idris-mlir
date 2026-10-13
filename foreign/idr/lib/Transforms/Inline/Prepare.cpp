// The force preparation: two rewrites of forces into calls that the inliner
// can then see through. Neither is a canonicalization pattern. One builds a
// function, which inside the inliner's pipeline would come after the call
// graph was taken; the other asks whether a function may be running, which
// only the references among functions answer. So idr-inline runs both on
// the module first, each on the roots it collected, under a greedy driver
// that neither folds nor simplifies regions: a fold would report a change no
// analysis needs dropped, and the round's canonicalize makes it anyway.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Inline.h"
#include "idr/IR/Grades.h"
#include "idr/Analysis/References.h"

#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "mlir/Transforms/GreedyPatternRewriteDriver.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DenseSet.h"

#include <optional>
#include <string>
#include <tuple>

using namespace mlir;

namespace {

// The argument `fn` forces and returns, when its body is only that: the
// wrappers ForceAtCapture sees through. Two operations, looked at one by
// one: the list's size walks every operation in the body, and this runs on
// every closure the driver visits.
std::optional<unsigned> forcedArgument(idr::FuncOp fn) {
  if (fn.isExternal() || !llvm::hasSingleElement(fn.getBody()))
    return std::nullopt;
  Block &body = fn.getBody().front();
  Block::iterator it = body.begin();
  auto force = it == body.end() ? idr::ForceOp() : dyn_cast<idr::ForceOp>(&*it);
  if (!force || ++it == body.end())
    return std::nullopt;
  auto ret = dyn_cast<idr::ReturnOp>(&*it);
  auto arg = dyn_cast<BlockArgument>(force.getSuspension());
  if (!ret || ++it != body.end() || ret.getNumOperands() != 1 ||
      ret.getOperand(0) != force.getResult() || !arg || arg.getOwner() != &body)
    return std::nullopt;
  return arg.getArgNumber();
}

// What one run of ForceAtCapture knows: the table it looks up and enters
// functions in, the functions it built for a (wrapper, argument, callee),
// and how many it built for each wrapper. A capture is reused only within
// the run: its name is never read back.
struct CaptureRun {
  SymbolTable &symbols;
  llvm::DenseMap<std::tuple<Operation *, unsigned, Operation *>, idr::FuncOp> built;
  llvm::DenseMap<Operation *, unsigned> count;
};

// `\_ => force thunk`, with the thunk used only there. The call replaces
// the suspension inside the continuation, so the cell is never built and
// the call stays where the force was: a tail call of the continuation
// stays one.
struct ForceAtCapture : OpRewritePattern<idr::ClosureOp> {
  ForceAtCapture(MLIRContext *context, CaptureRun &run)
      : OpRewritePattern(context), run(run) {}

  LogicalResult matchAndRewrite(idr::ClosureOp closure, PatternRewriter &rewriter) const override {
    auto wrapper = run.symbols.lookup<idr::FuncOp>(closure.getCalleeAttr().getAttr());
    std::optional<unsigned> forced = wrapper ? forcedArgument(wrapper) : std::nullopt;
    if (!forced || *forced >= closure.getCaptures().size())
      return failure();
    unsigned index = *forced;
    auto suspend = closure.getCaptures()[index].getDefiningOp<idr::SuspendOp>();
    if (!suspend || !suspend.getResult().hasOneUse())
      return failure();
    auto callee = run.symbols.lookup<idr::FuncOp>(suspend.getCalleeAttr().getAttr());
    if (!callee || !llvm::hasSingleElement(callee.getBody()))
      return failure();
    auto nCaps = static_cast<unsigned>(suspend.getCaptures().size());
    SmallVector<Type> inputs;
    inputs.reserve(wrapper.getNumArguments() - 1 + nCaps);
    for (unsigned i = 0, n = wrapper.getNumArguments(); i < n; ++i) {
      if (i == index) {
        llvm::append_range(inputs, suspend.getCaptures().getTypes());
        continue;
      }
      inputs.push_back(wrapper.getArgument(i).getType());
    }
    auto type = FunctionType::get(rewriter.getContext(), inputs, wrapper.getResultTypes());
    std::tuple<Operation *, unsigned, Operation *> key{wrapper, index, callee};
    idr::FuncOp &fn = run.built[key];
    if (fn && fn.getFunctionType() != type)
      return failure();
    if (!fn)
      fn = buildCapture(rewriter, wrapper, callee, index, nCaps, type);
    rewriter.setInsertionPoint(closure);
    SmallVector<Value> captures;
    captures.reserve(closure.getCaptures().size() - 1 + nCaps);
    for (auto [i, cap] : llvm::enumerate(closure.getCaptures())) {
      if (i == index) {
        llvm::append_range(captures, suspend.getCaptures());
        continue;
      }
      captures.push_back(cap);
    }
    auto neu = idr::ClosureOp::create(rewriter, closure.getLoc(), closure.getType(),
                                      FlatSymbolRefAttr::get(fn.getSymNameAttr()), captures);
    rewriter.replaceOp(closure, neu.getResult());
    rewriter.eraseOp(suspend);
    return success();
  }

private:
  // The body is the callee's, with its parameters where the wrapper took the
  // suspension, so the function has the facts of the body it copies. Like
  // every function a pass derives, it is named after its parent and entered
  // through the table, which renames a collision.
  idr::FuncOp buildCapture(PatternRewriter &rewriter, idr::FuncOp wrapper, idr::FuncOp callee,
                           unsigned index, unsigned nCaps, FunctionType type) const {
    rewriter.setInsertionPoint(wrapper);
    std::string name = (wrapper.getSymName() + ".capture" + Twine(++run.count[wrapper])).str();
    auto fn = idr::FuncOp::create(rewriter, wrapper.getLoc(), name, type,
                                  /*sym_visibility=*/{}, /*arg_attrs=*/{}, /*res_attrs=*/{},
                                  callee.getTotal(), /*break_last=*/false, /*no_inline=*/false,
                                  callee.getEffectsAttr(), /*instance=*/{}, /*clone=*/{});
    fn.setPrivate();
    run.symbols.insert(fn);
    ArrayRef<Type> inputs = type.getInputs();
    Block *entry = rewriter.createBlock(&fn.getBody(), fn.getBody().end(), inputs,
                                        SmallVector<Location>(inputs.size(), wrapper.getLoc()));
    IRMapping mapping;
    for (unsigned i = 0; i < nCaps; ++i)
      mapping.map(callee.getArgument(i), entry->getArgument(index + i));
    rewriter.setInsertionPointToStart(entry);
    for (Operation &op : callee.getBody().front())
      rewriter.clone(op, mapping);
    return fn;
  }

  CaptureRun &run;
};

// What one run of ForceOfOneConstant knows: the function each root's
// constant names, and the component of the references among functions each
// function is in.
struct ConstantRun {
  llvm::DenseMap<Operation *, idr::FuncOp> labels;
  llvm::DenseMap<Operation *, unsigned> component;

  // Whether `holder` may run while `label` runs. The holder names the label,
  // since the constant is one of its sites, so the label reaches the holder
  // exactly when the two are on one cycle of references: in one component.
  bool mayRunWithin(idr::FuncOp label, idr::FuncOp holder) const {
    auto from = component.find(label);
    auto to = component.find(holder);
    return from != component.end() && to != component.end() && from->second == to->second;
  }
};

// A constant suspension is a static cell every function that holds it
// shares. Forced where its label cannot be running, the call is the force,
// and inlining then sees the body. Where the label may be running, as in a
// knot whose label holds its own constant, the force must meet the cell's
// running state, which a call would recurse past. A second force keeps the
// cell, which is where a pure constant is computed once.
struct ForceOfOneConstant : OpRewritePattern<idr::ForceOp> {
  ForceOfOneConstant(MLIRContext *context, const ConstantRun &run)
      : OpRewritePattern(context), run(run) {}

  LogicalResult matchAndRewrite(idr::ForceOp force, PatternRewriter &rewriter) const override {
    idr::FuncOp fn = run.labels.lookup(force);
    if (!fn || !force.getSuspension().hasOneUse())
      return failure();
    Attribute attr;
    if (!matchPattern(force.getSuspension(), m_Constant(&attr)))
      return failure();
    auto closure = dyn_cast<idr::ClosureAttr>(attr);
    if (!closure || closure.getCallee().getAttr() != fn.getSymNameAttr() ||
        closure.getCaptures().size() > fn.getNumArguments())
      return failure();
    auto holder = force->getParentOfType<idr::FuncOp>();
    if (!holder || run.mayRunWithin(fn, holder))
      return failure();
    Dialect *dialect = rewriter.getContext()->getLoadedDialect<idr::IdrDialect>();
    SmallVector<Value> operands;
    operands.reserve(closure.getCaptures().size());
    for (auto [value, type] : llvm::zip(closure.getCaptures(), fn.getArgumentTypes())) {
      Operation *plain =
          dialect->materializeConstant(rewriter, value, idr::unrestricted(type), force.getLoc());
      if (!plain)
        return failure();
      operands.push_back(plain->getResult(0));
    }
    Operation *constant = force.getSuspension().getDefiningOp();
    // A new call, so it carries no effects: the next idr-effects writes them.
    rewriter.replaceOpWithNewOp<idr::CallOp>(force, TypeRange(force.getResult().getType()),
                                             closure.getCallee(), operands,
                                             /*arg_attrs=*/nullptr, /*res_attrs=*/nullptr,
                                             /*effects=*/nullptr);
    // Gone with its one use, so the References taken next lists no site of it.
    rewriter.eraseOp(constant);
    return success();
  }

  const ConstantRun &run;
};

// The driver over the collected roots only, within the module's body.
GreedyRewriteConfig preparationConfig(ModuleOp module, GreedyRewriteStrictness strictness) {
  GreedyRewriteConfig config;
  config.setScope(&module.getBodyRegion())
      .setStrictness(strictness)
      .enableFolding(false)
      .enableConstantCSE(false)
      .setRegionSimplificationLevel(GreedySimplifyRegionLevel::Disabled);
  return config;
}

} // namespace

namespace idr::inlining {

SmallVector<FuncOp> forceWrappers(ModuleOp module) {
  SmallVector<FuncOp> wrappers;
  for (FuncOp fn : module.getOps<FuncOp>())
    if (forcedArgument(fn))
      wrappers.push_back(fn);
  return wrappers;
}

bool forceAtCapture(ModuleOp module, SymbolTable &symbols, ArrayRef<FuncOp> wrappers) {
  llvm::DenseSet<StringAttr> names;
  for (FuncOp wrapper : wrappers)
    names.insert(wrapper.getSymNameAttr());
  // Each function's closures of a wrapper go to its own slot, read in
  // parallel; the slots are joined in module order.
  SmallVector<FuncOp> functions(module.getOps<FuncOp>());
  SmallVector<SmallVector<Operation *>> slots(functions.size());
  parallelFor(module.getContext(), 0, functions.size(), [&](size_t at) {
    functions[at].getBody().walk([&](ClosureOp closure) {
      if (names.contains(closure.getCalleeAttr().getAttr()))
        slots[at].push_back(closure);
    });
  });
  SmallVector<Operation *> roots;
  for (SmallVector<Operation *> &slot : slots)
    llvm::append_range(roots, slot);
  if (roots.empty())
    return false;

  CaptureRun run{symbols, {}, {}};
  RewritePatternSet patterns(module.getContext());
  patterns.add<ForceAtCapture>(module.getContext(), run);
  // A closure the rewrite builds, or one in a body it copies, may name a
  // wrapper again, as a chain of wrappers does. A run that does not converge
  // leaves valid IR.
  bool changed = false;
  (void)applyOpPatternsGreedily(
      roots, std::move(patterns),
      preparationConfig(module, GreedyRewriteStrictness::ExistingAndNewOps), &changed);
  return changed;
}

bool forceOfOneConstant(ModuleOp module, const References &references) {
  ConstantRun run;
  SmallVector<Operation *> roots;
  for (FuncOp fn : references.functions()) {
    for (auto [target, at] : references.of(fn)) {
      if (!at->hasTrait<OpTrait::ConstantLike>() || at->getNumResults() != 1 ||
          !at->getResult(0).hasOneUse())
        continue;
      auto force = dyn_cast<ForceOp>(*at->getResult(0).user_begin());
      if (!force || force.getSuspension() != at->getResult(0))
        continue;
      // A constant whose captures hold closures has a site for each; the
      // label is the one the outer closure names.
      Attribute attr;
      (void)matchPattern(at->getResult(0), m_Constant(&attr));
      auto closure = dyn_cast_if_present<ClosureAttr>(attr);
      if (!closure || closure.getCallee().getAttr() != target.getSymNameAttr())
        continue;
      if (run.labels.try_emplace(force, target).second)
        roots.push_back(force);
    }
  }
  if (roots.empty())
    return false;
  for (auto [index, members] : llvm::enumerate(references.components()))
    for (FuncOp fn : members)
      run.component.try_emplace(fn, static_cast<unsigned>(index));

  RewritePatternSet patterns(module.getContext());
  patterns.add<ForceOfOneConstant>(module.getContext(), run);
  bool changed = false;
  (void)applyOpPatternsGreedily(roots, std::move(patterns),
                                preparationConfig(module, GreedyRewriteStrictness::ExistingOps),
                                &changed);
  return changed;
}

} // namespace idr::inlining
