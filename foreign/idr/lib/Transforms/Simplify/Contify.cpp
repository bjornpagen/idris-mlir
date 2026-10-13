// idr-contify: a private idr.func whose one use is a call from another
// function is inlined there, with MLIR's inlineCall, and erased.
//
// Idris lifts every `case` and `if` on the right-hand side of a clause into
// a function of its own, a case block, which its parent calls once. The
// case block is a continuation of its parent, and it often calls the parent
// back, as recursion through an `if` does. MLIR's inliner refuses such a
// callee, one that calls its caller, so the parent and the case block stay
// two functions. Then a cell the parent takes apart cannot be reused by the
// constructor the case block builds, and case-of-case moves the call into
// both arms of the parent's matches, after which it has two calls and is
// no longer a continuation of anything.
// Inlining the one call copies no code, and the call goes; the parent keeps
// Idris's proof of termination only if the case block had it too
// (FuncOp::absorb). So idr-contify runs
// before the simplify loop, on the module Emit wrote, where every case block
// still has its one call. It uses inlineCall rather than the inliner, whose
// policy over the call graph is what refuses these callees. A callee that
// does not call its caller back is left to that inliner, which weighs it
// among the rest: inlined here, a helper called once (a balance of a tree),
// or a case block of one of two mutually recursive functions, makes its
// caller too large to inline into the other, and the cells one takes apart
// can no longer be reused by the constructors the other builds.
//
// A function with a second call, a call of its own, or a use that is not a
// call (a clone's fact names the clone) is left alone: it is not a
// continuation. Each step erases a function, so the pass ends. Each step
// also reads what the step before it moved, so the steps are serial.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/Simplify.h"
#include "idr/Analysis/Holds.h"
#include "idr/IR/Layout.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Transforms/Inliner.h"
#include "mlir/Transforms/InliningUtils.h"

#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

namespace idr {
#define GEN_PASS_DEF_IDRCONTIFY
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace {

// The call that is the one use of `fn`, when `fn` is a continuation of the
// function that makes it; null otherwise.
idr::CallOp continuationCall(idr::FuncOp fn, ArrayRef<Operation *> users) {
  if (fn.isPublic() || fn.isExternal() || users.size() != 1)
    return nullptr;
  auto call = dyn_cast<idr::CallOp>(users.front());
  if (!call || call->getParentOfType<idr::FuncOp>() == fn)
    return nullptr;
  return call;
}

// Inlines every continuation of `module` into the function that calls it,
// and erases it through `symbols`; returns how many.
unsigned contify(ModuleOp module, SymbolTable &symbols) {
  unsigned contified = 0;
  // The users of every function, over the module's region. Inlining moves
  // the callee's ops into the caller, so the users found here stay the
  // users; only the call inlined goes, listed under the function erased
  // with it, whose own attributes name no symbol but itself. A body moved
  // into its caller changes the function its calls sit in, and so which
  // callees call their caller back, so the sweeps go on until nothing
  // changes.
  SymbolTableCollection tables;
  SymbolUserMap users(tables, module);
  InlinerInterface interface(module.getContext());
  InlinerConfig config;
  for (bool changed = true; changed;) {
    changed = false;
    // Which functions each function uses, as the sweep begins.
    llvm::DenseMap<Operation *, llvm::SmallPtrSet<Operation *, 4>> uses;
    for (idr::FuncOp fn : module.getOps<idr::FuncOp>())
      for (Operation *user : users.getUsers(fn))
        if (auto caller = user->getParentOfType<idr::FuncOp>())
          uses[caller].insert(fn);
    for (idr::FuncOp fn : llvm::make_early_inc_range(module.getOps<idr::FuncOp>())) {
      idr::CallOp call = continuationCall(fn, users.getUsers(fn));
      if (!call)
        continue;
      auto caller = call->getParentOfType<idr::FuncOp>();
      auto used = uses.find(fn);
      if (used == uses.end() || !used->second.contains(caller))
        continue;
      // A body that does not return to the call (it ends in ub.unreachable)
      // goes in as a block of its own, which a match or a loop region cannot
      // hold. The inliner leaves such a call alone, and so does this.
      if (!interface.allowSingleBlockOptimization(fn.getBody()) &&
          call->getParentOp()->mightHaveTrait<OpTrait::SingleBlock>())
        continue;
      if (failed(inlineCall(interface, config.getCloneCallback(), call, fn, &fn.getBody(),
                            /*shouldCloneInlinedRegion=*/false)))
        continue;
      caller.absorb(fn);
      call.erase();
      symbols.erase(fn);
      ++contified;
      changed = true;
    }
  }
  return contified;
}

struct Contify : idr::impl::IdrContifyBase<Contify> {
  void runOnOperation() override {
    unsigned contified = contify(getOperation(), getAnalysis<SymbolTable>());
    numContified += contified;
    if (!contified)
      return markAllAnalysesPreserved();
    // No declaration changed, and every symbol erased went through the
    // table.
    markAnalysesPreserved<SymbolTable, idr::Holds, idr::TypeGraph, idr::Layouts>();
  }
};

} // namespace
