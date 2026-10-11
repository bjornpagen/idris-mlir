// idr.facts:infer: what idr-effects finds, before it records it: what each
// function reaches, and what flows to it from what it reaches. The pass
// keeps the answer across the rounds that run it: a function whose body is
// unchanged is reused, and a body that changed is inferred again.
export module idr.facts:infer;

import idr.mlir;
import idr.dialect;

import :closurelabel;
import :effects;
import :mayholdworld;

using namespace mlir;

export namespace idr::facts {

// The effects of one module's functions, kept by the pass that records them.
// idr-simplify runs that pass every round. The walk of a body and the
// interface lookup on each op answer the same effects while the body is the
// one already inferred, so a later round reuses them. A body that changed is
// walked again, and the effects are propagated again: a caller takes on what
// the functions it reaches may do.
export class Inferred {
public:
  Inferred();
  ~Inferred();

  // Whether each function of `module` may perform IO, crash or diverge.
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
  // closure may do too (passed).
  //
  // A function may diverge when its own body may: it lacks `idr.total`,
  // Idris's proof that every loop of it terminates. And it may when it
  // reaches one that may, the same way as a crash. That holds through a
  // function Idris proved too: its proof counts the calls Idris saw, and a
  // call of an interface's method, which reaches the implementation only
  // once the dictionary is known, is not one of them.
  //
  // A function without a body, and every function that reaches one or calls
  // anything but a func.func, may do all three.
  llvm::SmallVector<std::pair<func::FuncOp, Effects>> infer(ModuleOp module);

private:
  struct Cache;
  std::unique_ptr<Cache> cache;
};

} // namespace idr::facts

namespace {

void add(llvm::SHA1 &sha, const void *pointer) {
  sha.update(llvm::ArrayRef<uint8_t>(reinterpret_cast<const uint8_t *>(&pointer), sizeof(pointer)));
}

void add(llvm::SHA1 &sha, uint64_t value) {
  sha.update(llvm::ArrayRef<uint8_t>(reinterpret_cast<const uint8_t *>(&value), sizeof(value)));
}

void add(llvm::SHA1 &sha, uint8_t value) {
  sha.update(llvm::ArrayRef<uint8_t>(reinterpret_cast<const uint8_t *>(&value), sizeof(value)));
}

// The ops of `op`'s regions, in the order a later round walks them again.
void addOp(llvm::SHA1 &sha, Operation *op) {
  add(sha, static_cast<const void *>(op));
  add(sha, static_cast<const void *>(op->getParentOp()));
  add(sha, op->getRawDictionaryAttrs().getAsOpaquePointer());
  add(sha, static_cast<uint64_t>(static_cast<size_t>(op->hashProperties())));
  add(sha, op->getLoc().getAsOpaquePointer());
  for (Region &region : op->getRegions()) {
    for (Block &block : region) {
      add(sha, static_cast<const void *>(&block));
      for (BlockArgument arg : block.getArguments()) {
        add(sha, arg.getAsOpaquePointer());
        add(sha, arg.getType().getAsOpaquePointer());
      }
    }
  }
  for (Value operand : op->getOperands())
    add(sha, operand.getAsOpaquePointer());
  for (unsigned i = 0, n = op->getNumSuccessors(); i < n; ++i)
    add(sha, static_cast<const void *>(op->getSuccessor(i)));
  for (Type type : op->getResultTypes())
    add(sha, type.getAsOpaquePointer());
}

// What a later round compares with the body it inferred from. The effects
// attribute is written afterwards from the answer, so a round that only
// records the effects it just found leaves this the same. The signature,
// the name, `idr.total` and every op of the body are what inference reads.
std::array<uint8_t, 20> bodyStamp(func::FuncOp fn) {
  llvm::SHA1 sha;
  add(sha, fn.getSymNameAttr().getAsOpaquePointer());
  add(sha, fn.getFunctionType().getAsOpaquePointer());
  add(sha, fn->getAttr("idr.total").getAsOpaquePointer());
  add(sha, static_cast<uint8_t>(fn.isExternal()));
  if (!fn.isExternal()) {
    for (Block &block : fn.getBody()) {
      add(sha, static_cast<const void *>(&block));
      for (BlockArgument arg : block.getArguments()) {
        add(sha, arg.getAsOpaquePointer());
        add(sha, arg.getType().getAsOpaquePointer());
      }
    }
    fn.getBody().walk([&](Operation *op) { addOp(sha, op); });
  }
  return sha.result();
}

} // namespace

namespace idr::facts {

struct Inferred::Cache {
  // What reaching something does to a function: an op that may crash makes
  // it crash, a body without Idris's proof makes it diverge, and something
  // unknown (a function without a body, a call of anything but a func.func)
  // makes it do anything. IO a function does with a world it takes is not
  // reached: it is read off its type; IO on a world it forges (idr.world.new)
  // is reached. `names` is the symbol each reach resolved, kept beside it:
  // the body is inferred again when that function is gone or carries another
  // name.
  struct Found {
    idr::Effect reached = idr::Effect::none;
    llvm::SetVector<func::FuncOp> reaches;
    llvm::SmallVector<StringAttr> names;
  };

  struct Entry {
    std::array<uint8_t, 20> body{};
    Found local;
    bool takesWorld = false;
    Effects effects;
  };

  static constexpr idr::Effect crashes = idr::Effect::crash;
  static constexpr idr::Effect unknown =
      idr::Effect::io | idr::Effect::crash | idr::Effect::diverge;

  static void reach(Found &found, func::FuncOp target) {
    if (found.reaches.insert(target))
      found.names.push_back(target.getSymNameAttr());
  }

  // What `fn` does itself, and which functions it reaches.
  static Found local(func::FuncOp fn, SymbolTableCollection &symbols) {
    Found found;
    if (fn.isExternal()) {
      found.reached = unknown;
      return found;
    }
    if (!fn->hasAttr("idr.total"))
      found.reached = idr::Effect::diverge;
    auto resolve = [&](Operation *from, SymbolRefAttr callee) {
      if (auto target = symbols.lookupNearestSymbolFrom<func::FuncOp>(from, callee))
        reach(found, target);
      else
        found.reached = found.reached | unknown;
    };
    auto reachLabel = [&](Operation *from, SymbolRefAttr ctor) {
      if (StringAttr label = closureLabel(from, ctor))
        resolve(from, FlatSymbolRefAttr::get(label));
    };
    fn.getBody().walk([&](Operation *op) {
      if (auto mayCrash = dyn_cast<idr::MayCrashOpInterface>(op);
          mayCrash && mayCrash.getCrashCause())
        found.reached = found.reached | crashes;
      // A world forged in the body: IO that no world parameter announces.
      if (isa<idr::WorldNewOp>(op))
        found.reached = found.reached | idr::Effect::io;
      if (auto call = dyn_cast<func::CallOp>(op))
        resolve(op, call.getCalleeAttr());
      else if (auto closure = dyn_cast<idr::ClosureOp>(op))
        resolve(op, closure.getCalleeAttr());
      else if (auto suspend = dyn_cast<idr::SuspendOp>(op))
        resolve(op, suspend.getCalleeAttr());
      else if (auto con = dyn_cast<idr::ConOp>(op))
        reachLabel(op, con.getCtor());
      else if (isa<CallOpInterface>(op) && !isa<idr::ApplyOp>(op))
        found.reached = found.reached | unknown;
      op->getAttrDictionary().walk([&](Attribute nested) {
        if (auto closure = dyn_cast<idr::ClosureAttr>(nested))
          resolve(op, closure.getCallee());
        else if (auto con = dyn_cast<idr::ConAttr>(nested))
          reachLabel(op, con.getCtor());
      });
    });
    return found;
  }

  // Each fact flows from a function to those that reach it. `facts` holds
  // the body's own reaches; the bits that flow in are written on that copy.
  static void propagate(llvm::DenseMap<func::FuncOp, Found> &facts) {
    llvm::DenseMap<func::FuncOp, SmallVector<func::FuncOp>> reachedFrom;
    SmallVector<func::FuncOp> worklist;
    for (auto &[fn, found] : facts) {
      for (func::FuncOp callee : found.reaches)
        reachedFrom[callee].push_back(fn);
      if (found.reached != idr::Effect::none)
        worklist.push_back(fn);
    }
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
  }

  static bool reachesCurrent(const Found &found, const llvm::DenseSet<func::FuncOp> &live) {
    if (found.reaches.size() != found.names.size())
      return false;
    for (auto [index, callee] : llvm::enumerate(found.reaches))
      if (!live.contains(callee) || callee.getSymNameAttr() != found.names[index])
        return false;
    return true;
  }

  llvm::SmallVector<std::pair<func::FuncOp, Effects>> run(ModuleOp module) {
    if (cached != module) {
      entries.clear();
      cached = module;
    }
    llvm::DenseSet<func::FuncOp> live;
    SmallVector<func::FuncOp> funcs;
    for (func::FuncOp fn : module.getOps<func::FuncOp>()) {
      live.insert(fn);
      funcs.push_back(fn);
    }
    SmallVector<func::FuncOp> gone;
    for (const auto &entry : entries)
      if (!live.contains(entry.first))
        gone.push_back(entry.first);
    for (func::FuncOp fn : gone)
      entries.erase(fn);

    struct Seen {
      func::FuncOp fn;
      std::array<uint8_t, 20> body{};
      bool reuse = false;
    };
    SmallVector<Seen> seen;
    seen.reserve(funcs.size());
    bool unchanged = true;
    for (func::FuncOp fn : funcs) {
      Seen item;
      item.fn = fn;
      item.body = bodyStamp(fn);
      auto known = entries.find(fn);
      item.reuse = known != entries.end() && known->second.body == item.body &&
                   reachesCurrent(known->second.local, live);
      if (!item.reuse)
        unchanged = false;
      seen.push_back(std::move(item));
    }
    // Every function still has the body the effects were inferred from, and
    // the functions it reaches are the ones it resolved.
    if (unchanged) {
      llvm::SmallVector<std::pair<func::FuncOp, Effects>> out;
      out.reserve(seen.size());
      for (const Seen &item : seen)
        out.emplace_back(item.fn, entries.find(item.fn)->second.effects);
      return out;
    }

    // A type is walked once for a world, and that walk looks each declaration
    // up in one table. Nothing here adds, erases or renames a symbol. A data
    // declaration is not rewritten by the rounds that run this again, so a
    // body that is unchanged keeps the world its parameters held.
    SymbolTable table(module);
    idr::SymbolScope scope(module, table);
    idr::HoldMemo memo(module.getContext());
    SymbolTableCollection symbols;
    llvm::DenseMap<Type, bool> worlds;
    auto takes = [&](func::FuncOp fn) {
      return llvm::any_of(fn.getArgumentTypes(), [&](Type type) {
        auto [known, fresh] = worlds.try_emplace(type, false);
        if (fresh)
          known->second = mayHoldWorld(fn, type);
        return known->second;
      });
    };

    for (const Seen &item : seen) {
      if (item.reuse)
        continue;
      Entry &entry = entries[item.fn];
      entry.body = item.body;
      entry.local = local(item.fn, symbols);
      entry.takesWorld = takes(item.fn);
    }
    llvm::DenseMap<func::FuncOp, Found> facts;
    for (const Seen &item : seen)
      facts.try_emplace(item.fn, entries.find(item.fn)->second.local);
    propagate(facts);

    llvm::SmallVector<std::pair<func::FuncOp, Effects>> out;
    out.reserve(seen.size());
    for (const Seen &item : seen) {
      Effects effects = Effects::from(facts.find(item.fn)->second.reached);
      effects.io |= entries.find(item.fn)->second.takesWorld;
      entries.find(item.fn)->second.effects = effects;
      out.emplace_back(item.fn, effects);
    }
    return out;
  }

  llvm::DenseMap<func::FuncOp, Entry> entries;
  ModuleOp cached;
};

Inferred::Inferred() : cache(std::make_unique<Cache>()) {}

Inferred::~Inferred() { cache.reset(); }

llvm::SmallVector<std::pair<func::FuncOp, Effects>> Inferred::infer(ModuleOp module) {
  return cache->run(module);
}

} // namespace idr::facts
