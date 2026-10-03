// idr-contify: a private function whose one use is a call from another
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
// (facts::inlined). So this runs
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
// call (a closure names it) is left alone: it is not a continuation. Each
// step erases a function, so the pass ends.

#include "idr/Idr.h"

#include "mlir/IR/SymbolTable.h"
#include "mlir/Transforms/Inliner.h"
#include "mlir/Transforms/InliningUtils.h"

#include "llvm/ADT/MapVector.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDRCONTIFY
#include "idr/Passes.h.inc"
} // namespace idr

import idr.facts;

namespace {

// The users of each symbol the module's functions refer to, in the order
// they are found.
llvm::MapVector<Attribute, SmallVector<Operation *, 1>> usersBySymbol(ModuleOp module) noexcept {
  llvm::MapVector<Attribute, SmallVector<Operation *, 1>> users;
  if (std::optional<SymbolTable::UseRange> uses = SymbolTable::getSymbolUses(&module.getBodyRegion()))
    for (const SymbolTable::SymbolUse &use : *uses)
      users[use.getSymbolRef().getRootReference()].push_back(use.getUser());
  return users;
}

// The call that is the one use of `fn`, when `fn` is a continuation of the
// function that makes it; null otherwise.
func::CallOp continuationCall(func::FuncOp fn, ArrayRef<Operation *> users) noexcept {
  if (fn.isPublic() || fn.isExternal() || users.size() != 1)
    return nullptr;
  auto call = dyn_cast<func::CallOp>(users.front());
  if (!call || call->getParentOfType<func::FuncOp>() == fn)
    return nullptr;
  return call;
}

struct Contify : idr::impl::IdrContifyBase<Contify> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    auto users = usersBySymbol(module);
    InlinerInterface interface(&getContext());
    InlinerConfig config;
    // Inlining moves the callee's ops into the caller, so the users found
    // above stay the users; only the call inlined goes, and the attributes
    // of the function erased. A function that one of those attributes named
    // may then have one use left, so the sweeps go on until nothing
    // changes.
    for (bool changed = true; changed;) {
      changed = false;
      // Which symbols each function uses, as the sweep begins.
      llvm::DenseMap<StringAttr, llvm::SmallDenseSet<StringAttr, 4>> callees;
      for (auto &[symbol, ops] : users)
        for (Operation *user : ops)
          if (auto caller = user->getParentOfType<func::FuncOp>())
            callees[caller.getSymNameAttr()].insert(cast<StringAttr>(symbol));
      for (auto fn : llvm::make_early_inc_range(module.getOps<func::FuncOp>())) {
        auto found = users.find(fn.getSymNameAttr());
        if (found == users.end())
          continue;
        func::CallOp call = continuationCall(fn, found->second);
        auto caller = call ? call->getParentOfType<func::FuncOp>() : func::FuncOp();
        if (!call ||
            !callees.lookup(fn.getSymNameAttr()).contains(caller.getSymNameAttr()) ||
            failed(inlineCall(interface, config.getCloneCallback(), call, fn, &fn.getBody(),
                              /*shouldCloneInlinedRegion=*/false)))
          continue;
        idr::facts::inlined(caller, fn);
        call.erase();
        users.erase(found);
        // The function's own attributes may name other symbols.
        for (auto &entry : users)
          llvm::erase(entry.second, fn.getOperation());
        fn.erase();
        ++numContified;
        changed = true;
      }
    }
  }
};

} // namespace
