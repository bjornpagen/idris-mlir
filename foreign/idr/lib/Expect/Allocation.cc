// no-heap-allocation: nothing allocates a heap cell, in one function and
// what it may call, or in the whole module. This is how a test states that
// a value stays off the heap, whatever ops show it.

#include "Expect/Expect.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;

namespace idr::expect {
namespace {

constexpr StringRef property = "no-heap-allocation";

// What `op` allocates, or nothing. An op says so by an Allocate effect; a
// closure is the one exception, Pure as a value but built in a cell at
// runtime.
std::optional<std::string> allocation(Operation *op) {
  if (isa<ClosureOp>(op))
    return "a closure of @" + cast<ClosureOp>(op).getCallee().str() + " is built";
  // idr.lin.enter and idr.lin.use allocate a new value, not memory; a cell
  // idr-stack keeps in its frame is stack memory.
  if (auto effects = dyn_cast<MemoryEffectOpInterface>(op)) {
    SmallVector<MemoryEffects::EffectInstance> all;
    effects.getEffects(all);
    if (llvm::any_of(all, [](const MemoryEffects::EffectInstance &effect) {
          return isa<MemoryEffects::Allocate>(effect.getEffect()) &&
                 !isa<LinResource, SideEffects::AutomaticAllocationScopeResource>(
                     effect.getResource());
        }))
      return (op->getName().getStringRef() + " allocates").str();
  }
  return std::nullopt;
}

} // namespace

LogicalResult noHeapAllocation(ModuleOp module, StringRef function) {
  SymbolTable symbols(module);
  SmallVector<func::FuncOp> reached;
  llvm::DenseSet<Operation *> seen;
  if (function.empty()) {
    for (auto fn : module.getOps<func::FuncOp>())
      reached.push_back(fn);
  } else {
    auto root = symbols.lookup<func::FuncOp>(function.ltrim('@'));
    if (!root)
      return fail(module.getLoc(), property) << "no function " << function;
    reached.push_back(root);
    seen.insert(root);
  }
  bool held = true;
  // In one function's scope, what it may call is in scope too: every
  // function it names, by a call or a closure.
  for (size_t next = 0; next < reached.size(); ++next) {
    func::FuncOp fn = reached[next];
    if (fn.isExternal() && !function.empty()) {
      fail(fn.getLoc(), property) << "@" << fn.getSymName() << " may be called, and its body is not in the module";
      held = false;
      continue;
    }
    fn.walk([&](Operation *op) {
      if (std::optional<std::string> found = allocation(op)) {
        fail(op->getLoc(), property) << *found << " in " << where(op);
        held = false;
      }
      if (function.empty())
        return;
      if (isa<ApplyOp>(op) && !matchPattern(op->getOperand(0), m_Constant())) {
        fail(op->getLoc(), property) << where(op) << " applies a closure made outside it";
        held = false;
      }
      if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(op))
        for (const SymbolTable::SymbolUse &use : *uses)
          if (auto callee = symbols.lookup<func::FuncOp>(use.getSymbolRef().getRootReference()))
            if (seen.insert(callee).second)
              reached.push_back(callee);
    });
  }
  return success(held);
}

} // namespace idr::expect
