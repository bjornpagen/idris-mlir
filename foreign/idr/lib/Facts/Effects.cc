// idr-effects: `idr.effects` on every function (Facts.h reads it).
//
// A call of a function may perform IO when it takes a world, as a
// parameter or in data one holds. That is a fact of its type: a world
// reaches a function only through its parameters, since no op makes one
// from nothing (no constant is a world, and a closure never captures one).
// So a function that only builds IO actions, as a fold that makes
// `a *> b` does, performs no IO; whoever runs an action gives it a world.
//
// A function may crash when it reaches an op that may crash, through the
// functions it calls and the labels of the closures it makes: an
// idr.closure, a closure constant, or a constructor of a sum of closures
// that idr-defunctionalize made. A closure's crash counts where it is made,
// not where it is applied: a call that passes one on is judged by what the
// closure may do too (Facts.h, passed).
//
// A function without a body, and every function that reaches one or calls
// anything but a func.func, may do both.

#include "Facts/Facts.h"

#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr {
#define GEN_PASS_DEF_IDREFFECTS
#include "idr/Passes.h.inc"
} // namespace idr

namespace {

struct Found {
  // It reaches a function without a body, or a call of something unknown.
  bool unknown = false;
  bool crash = false;
  // It reaches an IO op: idr.effect, the fact idr-specialize still reads.
  bool io = false;
  // The functions it calls and whose closures it makes.
  llvm::SetVector<func::FuncOp> reaches;
};

// What `fn` does itself, and which functions it reaches.
Found local(func::FuncOp fn, SymbolTableCollection &symbols) {
  Found found;
  if (fn.isExternal()) {
    found.unknown = true;
    return found;
  }
  auto reach = [&](Operation *from, SymbolRefAttr callee) {
    if (auto target = symbols.lookupNearestSymbolFrom<func::FuncOp>(from, callee))
      found.reaches.insert(target);
    else
      found.unknown = true;
  };
  auto reachLabel = [&](Operation *from, SymbolRefAttr ctor) {
    if (StringAttr label = idr::facts::closureLabel(ctor))
      reach(from, FlatSymbolRefAttr::get(label));
  };
  fn.getBody().walk([&](Operation *op) {
    if (op->hasTrait<idr::PerformsIO>())
      found.io = true;
    if (auto mayCrash = dyn_cast<idr::MayCrashOpInterface>(op); mayCrash && mayCrash.getCrashCause())
      found.crash = true;
    if (auto call = dyn_cast<func::CallOp>(op))
      reach(op, call.getCalleeAttr());
    else if (auto closure = dyn_cast<idr::ClosureOp>(op))
      reach(op, closure.getCalleeAttr());
    else if (auto con = dyn_cast<idr::ConOp>(op))
      reachLabel(op, con.getCtor());
    else if (isa<CallOpInterface>(op) && !isa<idr::ApplyOp>(op))
      found.unknown = true;
    op->getAttrDictionary().walk([&](Attribute nested) {
      if (auto closure = dyn_cast<idr::ClosureAttr>(nested))
        reach(op, closure.getCallee());
      else if (auto con = dyn_cast<idr::ConAttr>(nested))
        reachLabel(op, con.getCtor());
    });
  });
  return found;
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
    llvm::DenseMap<func::FuncOp, Found> facts;
    llvm::DenseMap<func::FuncOp, SmallVector<func::FuncOp>> reachedFrom;
    SmallVector<func::FuncOp> worklist;
    for (auto fn : module.getOps<func::FuncOp>()) {
      Found &found = facts[fn] = local(fn, symbols);
      for (func::FuncOp callee : found.reaches)
        reachedFrom[callee].push_back(fn);
      if (found.unknown || found.crash || found.io)
        worklist.push_back(fn);
    }
    // Each fact flows from a function to those that reach it.
    while (!worklist.empty()) {
      func::FuncOp callee = worklist.pop_back_val();
      const Found &from = facts[callee];
      bool unknown = from.unknown, crash = from.crash, io = from.io;
      for (func::FuncOp caller : reachedFrom.lookup(callee)) {
        Found &grown = facts[caller];
        bool changed = (unknown && !grown.unknown) || (crash && !grown.crash) || (io && !grown.io);
        grown.unknown |= unknown;
        grown.crash |= crash;
        grown.io |= io;
        if (changed)
          worklist.push_back(caller);
      }
    }
    llvm::DenseMap<Type, bool> worlds;
    auto takesWorld = [&](func::FuncOp fn) {
      return llvm::any_of(fn.getArgumentTypes(), [&](Type type) {
        auto [known, fresh] = worlds.try_emplace(type, false);
        if (fresh)
          known->second = idr::facts::mayHoldWorld(fn, type);
        return known->second;
      });
    };
    for (auto &[fn, found] : facts) {
      bool io = found.unknown || takesWorld(fn);
      bool crash = found.unknown || found.crash;
      idr::Effect bits = idr::Effect::none;
      if (io)
        bits = bits | idr::Effect::io;
      if (crash)
        bits = bits | idr::Effect::crash;
      fn->setAttr("idr.effects", idr::EffectAttr::get(ctx, bits));
      fn->setAttr("idr.effect",
                  StringAttr::get(ctx, found.unknown || found.io ? "effectful" : "pure"));
      if (crash)
        fn->setAttr("idr.may_crash", UnitAttr::get(ctx));
      else
        fn->removeAttr("idr.may_crash");
      markWritesFirst(fn, crash);
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
