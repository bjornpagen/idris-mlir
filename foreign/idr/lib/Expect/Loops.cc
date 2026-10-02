// constant-stack and counted-loop: what idr-tail-loops guarantees of a
// function, stated as properties of the call graph and of the loops, not as
// the ops that happen to show them.

#include "Expect/Expect.h"
#include "Passes/Scc.h"

using namespace mlir;

namespace idr::expect {
namespace {

// The functions the body of `fn` refers to: by calls, and by closures that
// name them. What the function's own attributes name (the clone it is)
// is provenance, not a call.
SmallVector<func::FuncOp> references(func::FuncOp fn, SymbolTable &symbols) {
  SmallVector<func::FuncOp> out;
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&fn.getBody()))
    for (const SymbolTable::SymbolUse &use : *uses)
      if (auto target = symbols.lookup<func::FuncOp>(use.getSymbolRef().getRootReference()))
        out.push_back(target);
  return out;
}

} // namespace

// Every recursion reachable from the function became a loop: no function it
// may call, itself included, is on a cycle of references. Functions without
// a body in the module call nothing back.
LogicalResult constantStack(ModuleOp module, StringRef function) {
  constexpr StringRef property = "constant-stack";
  SmallVector<func::FuncOp> reached = named(module, function, property);
  if (reached.empty())
    return failure();
  SymbolTable symbols(module);
  llvm::DenseSet<Operation *> seen(reached.begin(), reached.end());
  for (size_t next = 0; next < reached.size(); ++next)
    for (func::FuncOp callee : references(reached[next], symbols))
      if (seen.insert(callee).second)
        reached.push_back(callee);
  auto refers = [&](func::FuncOp fn) { return references(fn, symbols); };
  bool held = true;
  for (const SmallVector<func::FuncOp> &cycle :
       idr::passes::stronglyConnected<func::FuncOp>(reached, refers)) {
    if (cycle.size() == 1 && !llvm::is_contained(refers(cycle.front()), cycle.front()))
      continue;
    func::FuncOp first = cycle.front();
    InFlightDiagnostic error = fail(first.getLoc(), property)
                               << "the stack grows with the recursion of";
    for (func::FuncOp fn : cycle)
      error << " @" << fn.getSymName();
    held = false;
  }
  return success(held);
}

// The function (or a clone of it) loops, and every loop it has counts to a
// bound with a step: an scf.for, which says its trip count, and no
// scf.while.
LogicalResult countedLoop(ModuleOp module, StringRef function) {
  constexpr StringRef property = "counted-loop";
  SmallVector<func::FuncOp> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  unsigned counted = 0;
  bool held = true;
  for (func::FuncOp fn : functions)
    fn.walk([&](Operation *op) {
      if (isa<scf::ForOp>(op))
        ++counted;
      if (isa<scf::WhileOp>(op)) {
        fail(op->getLoc(), property) << "a loop of " << where(op) << " has no trip count";
        held = false;
      }
    });
  if (held && counted == 0) {
    fail(functions.front().getLoc(), property) << function << " has no loop";
    held = false;
  }
  return success(held);
}

// The body of a loop over an array runs once per element as one linalg
// operation after lowering, which the vectorizer can give lanes only when
// it holds words alone: a dup or a drop, an allocation or a call in it is
// a count, a cell or a function per element.
LogicalResult pureArrayLoops(ModuleOp module, StringRef function) {
  constexpr StringRef property = "pure-array-loops";
  SmallVector<Operation *> roots;
  if (function.empty()) {
    roots.push_back(module);
  } else {
    for (func::FuncOp fn : named(module, function, property))
      roots.push_back(fn);
    if (roots.empty())
      return failure();
  }
  bool held = true, found = false;
  auto impure = [](Operation *op) -> std::optional<StringRef> {
    if (isa<DupOp, DropOp>(op))
      return "changes a count";
    if (isa<CallOpInterface>(op))
      return "calls";
    auto effects = dyn_cast<MemoryEffectOpInterface>(op);
    if (!effects)
      return std::nullopt;
    SmallVector<MemoryEffects::EffectInstance> instances;
    effects.getEffects(instances);
    for (const MemoryEffects::EffectInstance &effect : instances)
      if (isa<MemoryEffects::Allocate>(effect.getEffect()) &&
          effect.getResource()->getResourceID() != LinResource::getResourceID())
        return "allocates";
    return std::nullopt;
  };
  for (Operation *root : roots)
    root->walk([&](Operation *loop) {
      if (!isa<ArrayGenerateOp, ArrayFoldOp>(loop))
        return;
      found = true;
      loop->getRegion(0).walk([&](Operation *op) {
        if (std::optional<StringRef> why = impure(op)) {
          fail(op->getLoc(), property) << op->getName() << " " << *why << " in the body of a "
                                       << loop->getName() << " in " << where(op);
          held = false;
        }
      });
    });
  if (!found) {
    fail(roots.front()->getLoc(), property) << "no loop over an array"
                                            << (function.empty() ? "" : " in ") << function;
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
