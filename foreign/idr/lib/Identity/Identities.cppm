// idr.identity:identities: the functions of a module that give back one of
// their arguments, found together, and every call of one made that
// argument.
//
// Every function starts out assumed to give back each argument that could
// be its result: of the result's type at any quantity, and holding
// something at runtime. A function that does not, under what is assumed of
// the rest, loses the assumption, and the functions that call it are
// checked again; what is left when nothing changes is the greatest
// fixpoint, so the functions of a mutual recursion are found together, and
// whatever order the functions are checked in finds the same ones.
// rebuilds says why the assumptions that are left hold.
//
// A function in the owned stage (a reference in its signature) gives back
// nothing, nor does one that takes a world, whose call is where its effects
// are ordered.
export module idr.identity:identities;

import idr.mlir;
import idr.dialect;

import :rebuilds;

using namespace mlir;
using namespace idr;

namespace {

// The arguments `fn` could give back.
SmallVector<unsigned, 1> candidates(func::FuncOp fn) {
  SmallVector<unsigned, 1> found;
  if (fn.isExternal() || fn.getNumResults() != 1)
    return found;
  auto owns = [](Type type) { return gradeOf(type).permission != Permission::None; };
  ArrayRef<Type> arguments = fn.getArgumentTypes();
  Type result = fn.getResultTypes().front();
  if (owns(result) || llvm::any_of(arguments, owns) ||
      llvm::any_of(arguments, [](Type type) { return isWorld(type); }))
    return found;
  for (auto [index, type] : llvm::enumerate(arguments))
    if (!isErased(type) && unrestricted(type) == unrestricted(result))
      found.push_back(static_cast<unsigned>(index));
  return found;
}

} // namespace

export namespace idr::identity {

// The argument each function of `module` that gives one back gives back.
DenseMap<Operation *, unsigned> identities(ModuleOp module) {
  // Nothing below adds, erases or renames a symbol.
  SymbolTable table(module);
  SymbolScope scope(module, table);
  Assumed assumed;
  SmallVector<func::FuncOp> functions;
  for (auto fn : module.getOps<func::FuncOp>()) {
    SmallVector<unsigned, 1> found = candidates(fn);
    if (found.empty())
      continue;
    assumed[fn.getSymNameAttr()] = std::move(found);
    functions.push_back(fn);
  }
  // The functions whose check an assumption about each function may decide:
  // those that call it.
  DenseMap<StringAttr, SetVector<Operation *>> callers;
  for (func::FuncOp fn : functions)
    fn.walk([&](func::CallOp call) {
      StringAttr callee = call.getCalleeAttr().getAttr();
      if (assumed.contains(callee))
        callers[callee].insert(fn.getOperation());
    });
  SetVector<Operation *> work;
  for (func::FuncOp fn : functions)
    work.insert(fn.getOperation());
  while (!work.empty()) {
    auto fn = cast<func::FuncOp>(work.pop_back_val());
    StringAttr name = fn.getSymNameAttr();
    auto it = assumed.find(name);
    if (it == assumed.end())
      continue;
    SmallVector<unsigned, 1> kept;
    for (unsigned argument : it->second)
      if (Rebuilds(fn, argument, assumed).givesBack())
        kept.push_back(argument);
    if (kept.size() == it->second.size())
      continue;
    if (kept.empty())
      assumed.erase(it);
    else
      it->second = std::move(kept);
    if (auto calling = callers.find(name); calling != callers.end())
      for (Operation *caller : calling->second)
        work.insert(caller);
  }
  DenseMap<Operation *, unsigned> found;
  for (func::FuncOp fn : functions)
    if (auto it = assumed.find(fn.getSymNameAttr()); it != assumed.end())
      found[fn.getOperation()] = it->second.front();
  return found;
}

// What elide did: the functions that give back an argument, and the calls
// of them made that argument.
struct Elided {
  unsigned functions = 0;
  unsigned calls = 0;
};

// Makes every call of a function of `module` that gives back an argument
// that argument, held at the quantity of the call's result. The function
// stays, for whatever else names it (a closure), and symbol-dce erases it
// once nothing does.
Elided elide(ModuleOp module) {
  DenseMap<Operation *, unsigned> found = identities(module);
  Elided elided;
  elided.functions = static_cast<unsigned>(found.size());
  if (found.empty())
    return elided;
  DenseMap<StringAttr, unsigned> given;
  for (auto [fn, argument] : found)
    given[cast<func::FuncOp>(fn).getSymNameAttr()] = argument;
  SmallVector<func::CallOp> calls;
  module.walk([&](func::CallOp call) {
    if (given.contains(call.getCalleeAttr().getAttr()))
      calls.push_back(call);
  });
  for (func::CallOp call : calls) {
    OpBuilder b(call);
    Value argument = call.getOperand(given.lookup(call.getCalleeAttr().getAttr()));
    Value result = call.getResult(0);
    result.replaceAllUsesWith(heldAs(b, call.getLoc(), argument, result.getType()));
    call.erase();
    ++elided.calls;
  }
  return elided;
}

} // namespace idr::identity
