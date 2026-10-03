// constant-stack: what idr-tail-loops and idr-tail-calls guarantee of a
// function, stated as a property of the call graph, not as the ops that
// happen to show it.
export module idr.expect:constantStack;

import idr.mlir;
import idr.graph;

import :named;
import :report;

using namespace mlir;

namespace idr::expect {

namespace {

// A function's reference to another: by a call, guaranteed a tail call or
// not, or by a closure or an address that names it.
struct Reference {
  Operation *target;
  bool tailCall;
};

// The functions the body of `fn`, a function, refers to. What the
// function's own attributes name (the clone it is) is provenance, not a
// call.
SmallVector<Reference> references(Operation *fn, SymbolTable &symbols) {
  SmallVector<Reference> out;
  Region &body = cast<FunctionOpInterface>(fn).getFunctionBody();
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&body))
    for (const SymbolTable::SymbolUse &use : *uses) {
      Operation *target = symbols.lookup(use.getSymbolRef().getRootReference());
      if (!isa_and_nonnull<FunctionOpInterface>(target))
        continue;
      auto call = dyn_cast<LLVM::CallOp>(use.getUser());
      out.push_back(
          {target, call && call.getTailCallKind() == LLVM::tailcallkind::TailCallKind::MustTail});
    }
  return out;
}

} // namespace

// No recursion reachable from the function the argument names grows the
// stack: every function it may call that is on a cycle of references
// reaches the others of its cycle only through guaranteed tail calls
// (`musttail`, which idr-tail-calls makes), so before idr-tail-calls none
// may be on a cycle at all: every recursion became a loop.
//
// No recursion reachable from the function grows the stack: each function it
// may call, itself included, that is on a cycle of references refers to the
// others of its cycle only by guaranteed tail calls, each of which replaces
// its caller's frame. Functions without a body in the module call nothing
// back.
export LogicalResult constantStack(ModuleOp module, StringRef function) {
  constexpr StringRef property = "constant-stack";
  SmallVector<Operation *> reached =
      llvm::map_to_vector(namedFunctions(module, function, property),
                          [](FunctionOpInterface fn) { return fn.getOperation(); });
  if (reached.empty())
    return failure();
  SymbolTable symbols(module);
  llvm::DenseSet<Operation *> seen(reached.begin(), reached.end());
  for (size_t next = 0; next < reached.size(); ++next)
    for (Reference ref : references(reached[next], symbols))
      if (seen.insert(ref.target).second)
        reached.push_back(ref.target);
  auto refers = [&](Operation *fn) {
    return llvm::map_to_vector(references(fn, symbols), [](Reference ref) { return ref.target; });
  };
  bool held = true;
  for (const SmallVector<Operation *> &cycle :
       idr::graph::stronglyConnected<Operation *>(reached, refers)) {
    llvm::DenseSet<Operation *> members(cycle.begin(), cycle.end());
    bool grows = false;
    for (Operation *fn : cycle)
      for (Reference ref : references(fn, symbols))
        grows |= members.contains(ref.target) && !ref.tailCall;
    if (!grows)
      continue;
    InFlightDiagnostic error = fail(cycle.front()->getLoc(), property)
                               << "the stack grows with the recursion of";
    for (Operation *fn : cycle)
      error << " @" << SymbolTable::getSymbolName(fn).getValue();
    held = false;
  }
  return success(held);
}

} // namespace idr::expect
