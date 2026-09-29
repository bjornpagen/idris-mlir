// Whether a call of a function performs IO while it runs, for raising.

#include "Specialize/Specializer.h"

#include "mlir/IR/Matchers.h"

#include "llvm/ADT/MapVector.h"

using namespace mlir;

namespace idr::specialize {

// Whether a call of `fn` may perform IO while it runs. idr.effect cannot
// say: idr-effects counts the effects of a closure where it is created, so
// a function that only builds IO actions (a fold that makes `a *> b` of
// each element, `pure ()` at the end) is effectful, although calling it
// performs nothing, and nothing its caller does can be reordered with it.
// Here a closure counts where it is applied instead: a function runs IO if
// it has an IO op, calls a function that runs IO, or applies a closure that
// is not built here or whose function runs IO. The facts of the functions
// `fn` reaches are found together, as a greatest fixpoint, so that a cycle
// of calls none of which does IO does none. A fact stays true for the rest
// of the run: specialization and raising only make an applied closure more
// known.
bool Specializer::runsIO(func::FuncOp fn) {
  if (auto known = performsIO.find(fn); known != performsIO.end())
    return known->second;
  struct Local {
    bool io = false;
    SmallVector<func::FuncOp> reaches;
  };
  llvm::MapVector<func::FuncOp, Local> found;
  SmallVector<func::FuncOp> stack{fn};
  while (!stack.empty()) {
    func::FuncOp f = stack.pop_back_val();
    if (performsIO.count(f) || found.count(f))
      continue;
    Local &local = found[f];
    auto reach = [&](FlatSymbolRefAttr name) {
      auto target = clones.symbols().lookup<func::FuncOp>(name.getAttr());
      if (!target) {
        local.io = true;
        return;
      }
      local.reaches.push_back(target);
      stack.push_back(target);
    };
    if (f.isExternal()) {
      local.io = true;
      continue;
    }
    f.getBody().walk([&](Operation *op) {
      if (op->hasTrait<PerformsIO>()) {
        local.io = true;
      } else if (auto call = dyn_cast<func::CallOp>(op)) {
        reach(call.getCalleeAttr());
      } else if (auto apply = dyn_cast<ApplyOp>(op)) {
        ClosureAttr constant;
        if (auto closure = apply.getCallee().getDefiningOp<ClosureOp>())
          reach(closure.getCalleeAttr());
        else if (matchPattern(apply.getCallee(), m_Constant(&constant)))
          reach(constant.getCallee());
        else
          local.io = true;
      } else if (isa<CallOpInterface>(op)) {
        local.io = true;
      }
    });
  }
  auto io = [&](func::FuncOp f) {
    auto known = performsIO.find(f);
    return known != performsIO.end() ? known->second : found.find(f)->second.io;
  };
  for (bool grew = true; grew;) {
    grew = false;
    for (auto &[f, local] : found)
      if (!local.io && llvm::any_of(local.reaches, io))
        local.io = grew = true;
  }
  for (auto &[f, local] : found)
    performsIO[f] = local.io;
  return performsIO.lookup(fn);
}

} // namespace idr::specialize
