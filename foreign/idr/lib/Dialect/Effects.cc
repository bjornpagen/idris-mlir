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

// Whether `fn`, given the string `s` and the world `world`, writes `s` before
// anything else it does with the world: then fn(s, xs, w) is
// fn("", xs, put_str(s, w)), and a caller can write the string itself.
// That holds when every use of the world writes `s` into it, or passes it to
// a call of `fn` itself whose string starts with `s` (`s` with strings
// appended, which that call writes first in turn), and `s` has no other use.
// The eager write moves output before what the body computes on the way, so
// `fn` must also return and never crash: a string written early must not be
// seen when the body would not have got to it.
bool writesFirst(func::FuncOp fn, BlockArgument s, BlockArgument world, bool crash) {
  if (!idr::isTotal(fn) || crash)
    return false;
  unsigned string = s.getArgNumber(), next = world.getArgNumber();
  auto passedOn = [&](Operation *user, unsigned operand) {
    auto call = dyn_cast<func::CallOp>(user);
    return call && call.getCallee() == fn.getSymName() && operand == string &&
           call.getOperand(next) == world;
  };
  for (OpOperand &use : world.getUses()) {
    Operation *user = use.getOwner();
    if (auto put = dyn_cast<idr::PutStrOp>(user); put && put.getStr() == s)
      continue;
    auto call = dyn_cast<func::CallOp>(user);
    if (!call || call.getCallee() != fn.getSymName() || use.getOperandNumber() != next)
      return false;
    Value passed = call.getOperand(string);
    while (passed != s) {
      auto append = passed.getDefiningOp<idr::StrAppendOp>();
      if (!append || !append->hasOneUse())
        return false;
      passed = append.getLhs();
    }
  }
  for (OpOperand &use : s.getUses()) {
    Operation *user = use.getOwner();
    if (auto put = dyn_cast<idr::PutStrOp>(user); put && put.getWorld() == world)
      continue;
    if (passedOn(user, use.getOperandNumber()))
      continue;
    // The start of a string appended to, up to the call it is passed to.
    Value start = s;
    Operation *at = user;
    unsigned operand = use.getOperandNumber();
    while (auto append = dyn_cast<idr::StrAppendOp>(at)) {
      if (operand != 0 || !append->hasOneUse())
        return false;
      start = append.getResult();
      OpOperand &following = *start.use_begin();
      at = following.getOwner();
      operand = following.getOperandNumber();
    }
    if (start == s || !passedOn(at, operand))
      return false;
  }
  return true;
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
      markWritesFirst(fn, fact.crash);
    }
  }

  // idr.writes_first on each string parameter that `fn` writes before
  // anything else it does with its one world.
  static void markWritesFirst(func::FuncOp fn, bool crash) {
    if (fn.isExternal())
      return;
    auto worlds = llvm::make_filter_range(fn.getArguments(), [](BlockArgument arg) {
      return isa<idr::WorldType>(arg.getType());
    });
    bool one = std::distance(worlds.begin(), worlds.end()) == 1;
    for (BlockArgument arg : fn.getArguments()) {
      if (!isa<idr::StrType>(arg.getType()))
        continue;
      if (one && writesFirst(fn, arg, *worlds.begin(), crash))
        fn.setArgAttr(arg.getArgNumber(), "idr.writes_first", UnitAttr::get(fn.getContext()));
      else
        fn.removeArgAttr(arg.getArgNumber(), "idr.writes_first");
    }
  }
};

} // namespace
