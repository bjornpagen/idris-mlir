// idr-effects: the facts idr.effect and idr.may_crash of every function.

#include "idr/Idr.h"

#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDREFFECTS
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

struct Facts {
  bool io = false;
  bool crash = false;
  // The functions this one reaches: those it calls, and those of the
  // closures it creates, whose effects count where they are created.
  llvm::SetVector<func::FuncOp> reaches;
};

// What `fn` does itself, and which functions it reaches. A call of anything
// but a func.func with a body does everything.
Facts localFacts(func::FuncOp fn, SymbolTableCollection &symbols) {
  Facts facts;
  if (fn.isExternal()) {
    facts.io = facts.crash = true;
    return facts;
  }
  auto reach = [&](Operation *from, SymbolRefAttr callee) {
    auto target = symbols.lookupNearestSymbolFrom<func::FuncOp>(from, callee);
    if (target)
      facts.reaches.insert(target);
    else
      facts.io = facts.crash = true;
  };
  fn.getBody().walk([&](Operation *op) {
    if (op->hasTrait<idr::PerformsIO>())
      facts.io = true;
    if (auto mayCrash = dyn_cast<idr::MayCrashOpInterface>(op); mayCrash && mayCrash.getCrashCause())
      facts.crash = true;
    if (auto call = dyn_cast<func::CallOp>(op))
      reach(op, call.getCalleeAttr());
    else if (auto closure = dyn_cast<idr::ClosureOp>(op))
      reach(op, closure.getCalleeAttr());
    else if (isa<CallOpInterface>(op) && !isa<idr::ApplyOp>(op))
      facts.io = facts.crash = true;
    op->getAttrDictionary().walk([&](idr::ClosureAttr closure) { reach(op, closure.getCallee()); });
  });
  return facts;
}

struct Effects : idr::impl::IdrEffectsBase<Effects> {
  void runOnOperation() override {
    ModuleOp module = getOperation();
    MLIRContext *ctx = &getContext();
    SymbolTableCollection symbols;
    llvm::DenseMap<func::FuncOp, Facts> facts;
    llvm::DenseMap<func::FuncOp, SmallVector<func::FuncOp>> reachedFrom;
    SmallVector<func::FuncOp> worklist;
    for (auto fn : module.getOps<func::FuncOp>()) {
      Facts &local = facts[fn] = localFacts(fn, symbols);
      for (func::FuncOp callee : local.reaches)
        reachedFrom[callee].push_back(fn);
      if (local.io || local.crash)
        worklist.push_back(fn);
    }
    // Each fact flows from a function to those that reach it.
    while (!worklist.empty()) {
      func::FuncOp callee = worklist.pop_back_val();
      bool io = facts[callee].io, crash = facts[callee].crash;
      for (func::FuncOp caller : reachedFrom.lookup(callee)) {
        Facts &grown = facts[caller];
        bool changed = (io && !grown.io) || (crash && !grown.crash);
        grown.io |= io;
        grown.crash |= crash;
        if (changed)
          worklist.push_back(caller);
      }
    }
    for (auto &[fn, fact] : facts) {
      fn->setAttr("idr.effect", StringAttr::get(ctx, fact.io ? "effectful" : "pure"));
      if (fact.crash)
        fn->setAttr("idr.may_crash", UnitAttr::get(ctx));
      else
        fn->removeAttr("idr.may_crash");
    }
  }
};

} // namespace
