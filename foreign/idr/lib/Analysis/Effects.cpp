// What each function may do, from what its body does itself and what it
// reaches. The bodies separate: each is walked on a worker into its own
// slot, for the ops that crash and the worlds it forges, and nothing else
// of the module is read there but the analyses already built. What a
// function reaches is the references' sites, so no body is walked for it.
//
// The bits flow from a function to every function that reaches it. Over
// the components of the references, callees first, that least fixpoint is
// one pass: a component's bits are the or of its members' own and of those
// of every function its members name outside it, each final already, and
// every member gets them. IO from a world taken as a parameter is added
// after the flow, not through it: a caller that passes a world on takes one
// itself, and one that forges a world reaches idr.world.new.
#include "idr/Analysis/Effects.h"

#include "idr/Analysis/Holds.h"
#include "idr/Analysis/References.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/TypeGraph.h"

#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/Sequence.h"

using namespace mlir;

namespace {

// What the walk of one body finds.
struct BodySlot {
  idr::Effect local = idr::Effect::none;
  bool world = false;
};

bool takes(const idr::Holds &holds, idr::FuncOp fn) {
  return llvm::any_of(fn.getArgumentTypes(), [&](Type type) { return holds.mayHoldWorld(type); });
}

// What `fn` does itself. A body without Idris's proof may diverge; an op
// that may crash makes it crash; a world forged in it is IO that no world
// parameter announces. Without a body, or with a call of something the
// references cannot follow, it may do anything.
idr::Effect local(idr::FuncOp fn, const idr::References &references) {
  if (fn.isExternal() || references.callsUnknown(fn))
    return idr::anyEffect;
  idr::Effect found = fn.getTotal() ? idr::Effect::none : idr::Effect::diverge;
  constexpr idr::Effect both = idr::Effect::crash | idr::Effect::io;
  fn.getBody().walk([&](Operation *op) {
    if (auto mayCrash = dyn_cast<idr::MayCrashOpInterface>(op);
        mayCrash && mayCrash.getCrashCause())
      found |= idr::Effect::crash;
    if (isa<idr::WorldNewOp>(op))
      found |= idr::Effect::io;
    return idr::bitEnumContainsAll(found, both) ? WalkResult::interrupt() : WalkResult::advance();
  });
  return found;
}

} // namespace

idr::Effects::Effects(Operation *module, AnalysisManager &am)
    : holds(am.getAnalysis<Holds>()), symbols(am.getAnalysis<mlir::SymbolTable>()) {
  const References &references = am.getAnalysis<References>();
  ArrayRef<FuncOp> fns = references.functions();
  unsigned n = static_cast<unsigned>(fns.size());
  for (unsigned at = 0; at < n; ++at) {
    FuncOp fn = fns[at];
    positions.try_emplace(fn.getOperation(), at);
  }
  SmallVector<BodySlot> slots(n);
  parallelForEach(module->getContext(), llvm::seq<size_t>(0, n), [&](size_t at) {
    FuncOp fn = fns[at];
    slots[at].local = local(fn, references);
    slots[at].world = takes(holds, fn);
  });

  SmallVector<Effect> reached(n, Effect::none);
  auto positionOf = [&](FuncOp fn) { return positions.lookup(fn.getOperation()); };
  for (const SmallVector<FuncOp> &component : references.components()) {
    Effect bits = Effect::none;
    for (FuncOp member : component) {
      bits |= slots[positionOf(member)].local;
      for (const References::Site &site : references.of(member)) {
        if (bits == anyEffect)
          break;
        bits |= reached[positionOf(site.target)];
      }
    }
    for (FuncOp member : component)
      reached[positionOf(member)] = bits;
  }

  answers.reserve(n);
  worlds.resize(n);
  for (unsigned at = 0; at < n; ++at) {
    answers.push_back(slots[at].world ? reached[at] | Effect::io : reached[at]);
    if (slots[at].world)
      worlds.set(at);
  }
}

bool idr::Effects::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<Effects>() || !pa.isPreserved<References>() ||
         !pa.isPreserved<Holds>() || !pa.isPreserved<TypeGraph>() ||
         !pa.isPreserved<mlir::SymbolTable>();
}

idr::Effect idr::Effects::of(FuncOp fn) const {
  auto found = positions.find(fn.getOperation());
  return found == positions.end() ? anyEffect : answers[found->second];
}

bool idr::Effects::takesWorld(FuncOp fn) const {
  auto found = positions.find(fn.getOperation());
  if (found != positions.end())
    return worlds.test(found->second);
  return fn && takes(holds, fn);
}

idr::Effect idr::Effects::declared(FuncOp fn) {
  if (!fn || fn.isExternal())
    return anyEffect;
  if (EffectAttr found = fn.getEffectsAttr())
    return found.getValue();
  return anyEffect;
}

// A label the module lacks may do anything, as `of` answers for a function
// it did not see.
idr::Effect idr::Effects::label(StringAttr name) const {
  return of(symbols.lookup<FuncOp>(name));
}

// What the closures in a constant may do, through its captures and fields.
// MLIR's walk reads each sub-attribute once, and a run's cells and its tail
// as its own, one level deep: never its fields along the spine, which would
// rebuild the rest of the run at every step. Every cell of a run is its
// constructor's, so the run's is the one to ask about.
idr::Effect idr::Effects::inConstant(Attribute constant) const {
  Effect out = Effect::none;
  constant.walk([&](Attribute nested) {
    if (auto closure = dyn_cast<ClosureAttr>(nested))
      out |= label(closure.getCallee().getAttr());
    else if (auto con = dyn_cast<ConAttr>(nested))
      if (StringAttr name = closureLabel(symbols, con.getCtor()))
        out |= label(name);
    return out == anyEffect ? WalkResult::interrupt() : WalkResult::advance();
  });
  return out;
}

// A value made here, as a constant, a closure or a constructor, holds the
// closures it is made of, and a value moved into or out of a linear type
// the closures of what it moved; any other value whose type admits a
// closure may hold any. A closure's label counts as the analysis finds it,
// not as the label's fact was last written.
idr::Effect idr::Effects::passed(Value value) const {
  Effect out = Effect::none;
  SmallVector<Value> work{value};
  llvm::SmallDenseSet<Value, 8> seen;
  while (!work.empty() && out != anyEffect) {
    Value next = work.pop_back_val();
    if (!seen.insert(next).second || !holds.mayHoldClosure(next.getType()))
      continue;
    Attribute constant;
    if (matchPattern(next, m_Constant(&constant))) {
      out |= inConstant(constant);
      continue;
    }
    Operation *def = next.getDefiningOp();
    if (auto closure = dyn_cast_or_null<ClosureOp>(def)) {
      out |= label(closure.getCalleeAttr().getAttr());
      llvm::append_range(work, closure.getCaptures());
      continue;
    }
    if (auto enter = dyn_cast_or_null<LinEnterOp>(def)) {
      work.push_back(enter.getValue());
      continue;
    }
    if (auto use = dyn_cast_or_null<LinUseOp>(def)) {
      work.push_back(use.getLinear());
      continue;
    }
    if (auto con = dyn_cast_or_null<ConOp>(def)) {
      if (StringAttr name = closureLabel(symbols, con.getCtor()))
        out |= label(name);
      llvm::append_range(work, con.getFields());
      continue;
    }
    return anyEffect;
  }
  return out;
}
