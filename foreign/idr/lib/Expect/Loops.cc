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
  func::FuncOp root = named(module, function, property);
  if (!root)
    return failure();
  SymbolTable symbols(module);
  SmallVector<func::FuncOp> reached{root};
  llvm::DenseSet<Operation *> seen{root};
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

// The function loops, and every loop it has counts to a bound with a step:
// an scf.for, which says its trip count, and no scf.while.
LogicalResult countedLoop(ModuleOp module, StringRef function) {
  constexpr StringRef property = "counted-loop";
  func::FuncOp fn = named(module, function, property);
  if (!fn)
    return failure();
  unsigned counted = 0;
  bool held = true;
  fn.walk([&](Operation *op) {
    if (isa<scf::ForOp>(op))
      ++counted;
    if (isa<scf::WhileOp>(op)) {
      fail(op->getLoc(), property) << "a loop of " << where(op) << " has no trip count";
      held = false;
    }
  });
  if (held && counted == 0) {
    fail(fn.getLoc(), property) << "@" << fn.getSymName() << " has no loop";
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
