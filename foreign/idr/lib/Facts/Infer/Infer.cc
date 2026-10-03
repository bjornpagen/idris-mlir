// What idr-effects finds: what each function reaches, and what flows to it
// from what it reaches.
module idr.facts;

import idr.mlir;

using namespace mlir;

namespace {

// What reaching something does to a function: an op that may crash makes
// it crash, a body without Idris's proof makes it diverge, and something
// unknown (a function without a body, a call of anything but a func.func)
// makes it do anything. IO a function does with a world it takes is not
// reached: it is read off its type; IO on a world it forges (idr.world.new)
// is reached.
constexpr idr::Effect crashes = idr::Effect::crash;
constexpr idr::Effect unknown = idr::Effect::io | idr::Effect::crash | idr::Effect::diverge;

struct Found {
  idr::Effect reached = idr::Effect::none;
  // The functions it calls and whose closures it makes.
  llvm::SetVector<func::FuncOp> reaches;
};

// What `fn` does itself, and which functions it reaches.
Found local(func::FuncOp fn, SymbolTableCollection &symbols) {
  Found found;
  if (fn.isExternal()) {
    found.reached = unknown;
    return found;
  }
  if (!fn->hasAttr("idr.total"))
    found.reached = idr::Effect::diverge;
  auto reach = [&](Operation *from, SymbolRefAttr callee) {
    if (auto target = symbols.lookupNearestSymbolFrom<func::FuncOp>(from, callee))
      found.reaches.insert(target);
    else
      found.reached = found.reached | unknown;
  };
  auto reachLabel = [&](Operation *from, SymbolRefAttr ctor) {
    if (StringAttr label = idr::facts::closureLabel(from, ctor))
      reach(from, FlatSymbolRefAttr::get(label));
  };
  fn.getBody().walk([&](Operation *op) {
    if (auto mayCrash = dyn_cast<idr::MayCrashOpInterface>(op); mayCrash && mayCrash.getCrashCause())
      found.reached = found.reached | crashes;
    // A world forged in the body: IO that no world parameter announces.
    if (isa<idr::WorldNewOp>(op))
      found.reached = found.reached | idr::Effect::io;
    if (auto call = dyn_cast<func::CallOp>(op))
      reach(op, call.getCalleeAttr());
    else if (auto closure = dyn_cast<idr::ClosureOp>(op))
      reach(op, closure.getCalleeAttr());
    else if (auto con = dyn_cast<idr::ConOp>(op))
      reachLabel(op, con.getCtor());
    else if (isa<CallOpInterface>(op) && !isa<idr::ApplyOp>(op))
      found.reached = found.reached | unknown;
    op->getAttrDictionary().walk([&](Attribute nested) {
      if (auto closure = dyn_cast<idr::ClosureAttr>(nested))
        reach(op, closure.getCallee());
      else if (auto con = dyn_cast<idr::ConAttr>(nested))
        reachLabel(op, con.getCtor());
    });
  });
  return found;
}

} // namespace

llvm::SmallVector<std::pair<func::FuncOp, idr::facts::Effects>>
idr::facts::infer(ModuleOp module) {
  SymbolTableCollection symbols;
  llvm::DenseMap<func::FuncOp, Found> facts;
  llvm::DenseMap<func::FuncOp, SmallVector<func::FuncOp>> reachedFrom;
  SmallVector<func::FuncOp> worklist;
  for (auto fn : module.getOps<func::FuncOp>()) {
    Found &found = facts[fn] = local(fn, symbols);
    for (func::FuncOp callee : found.reaches)
      reachedFrom[callee].push_back(fn);
    if (found.reached != idr::Effect::none)
      worklist.push_back(fn);
  }
  // Each fact flows from a function to those that reach it.
  while (!worklist.empty()) {
    func::FuncOp callee = worklist.pop_back_val();
    idr::Effect reached = facts[callee].reached;
    for (func::FuncOp caller : reachedFrom.lookup(callee)) {
      Found &grown = facts[caller];
      if ((grown.reached | reached) == grown.reached)
        continue;
      grown.reached = grown.reached | reached;
      worklist.push_back(caller);
    }
  }
  llvm::DenseMap<Type, bool> worlds;
  auto takes = [&](func::FuncOp fn) {
    return llvm::any_of(fn.getArgumentTypes(), [&](Type type) {
      auto [known, fresh] = worlds.try_emplace(type, false);
      if (fresh)
        known->second = mayHoldWorld(fn, type);
      return known->second;
    });
  };
  llvm::SmallVector<std::pair<func::FuncOp, Effects>> out;
  for (auto &[fn, found] : facts) {
    Effects effects;
    effects.io = bitEnumContainsAny(found.reached, idr::Effect::io) || takes(fn);
    effects.crash = bitEnumContainsAny(found.reached, idr::Effect::crash);
    effects.diverge = bitEnumContainsAny(found.reached, idr::Effect::diverge);
    out.emplace_back(fn, effects);
  }
  return out;
}
