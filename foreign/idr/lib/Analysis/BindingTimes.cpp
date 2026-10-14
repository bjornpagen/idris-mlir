// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The binding times of every parameter.
//
// The classes are found by abstract interpretation: each function on a
// cycle is interpreted over abstract values (a parameter, a proper part of
// one, or anything), and so is every function of its cycle that it reaches,
// once for each assignment of abstract values to its parameters, so the
// analysis ends. A cycle is a component of the references' graph, which
// References already holds. Each function's interpretation reads bodies and
// References alone and fills its own slot, so the functions are interpreted
// on workers and the slots merged in module order.
//
// A raised clone recurses where its callee does, though on no cycle of
// references until raising closes it: it runs its callee's body with the
// consumer at its tails, and a call of the callee there whose result is
// consumed alike becomes a call of the clone once inlining shows the
// consumer. Its parameters are its callee's, then the apply's arguments,
// and that recursion passes the callee's as the callee does and the
// apply's arguments as anything. So each parameter of a raised clone of a
// recursive callee has its callee's binding time as well as its own, and
// an apply's argument is other. A callee that is gone, or that takes other
// parameters now, makes no call that raising would turn into the clone.
#include "idr/Analysis/Specialize.h"

#include "idr/Analysis/References.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/Matchers.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVectorExtras.h"
#include "llvm/Support/ErrorHandling.h"

#include <set>
#include <utility>

using namespace mlir;

namespace idr {

llvm::StringRef nameOf(BindingTime time) {
  switch (time) {
  case BindingTime::Free:
    return "free";
  case BindingTime::Fixed:
    return "fixed";
  case BindingTime::Decreasing:
    return "decreasing";
  case BindingTime::Bounded:
    return "bounded";
  case BindingTime::Other:
    return "other";
  }
  llvm_unreachable("unknown binding time");
}

namespace {

// What a value is, in terms of the parameters of the function analyzed.
struct Abstract {
  enum class Kind : uint8_t { Top, Same, Smaller };
  Kind kind = Kind::Top;
  unsigned param = 0;

  static Abstract same(unsigned param) { return {Kind::Same, param}; }

  // One number per abstract value: anything is anything, whatever
  // parameter it was last seen as.
  unsigned code() const {
    return kind == Kind::Top ? 0 : 2 * param + (kind == Kind::Same ? 1 : 2);
  }

  // A proper part of what `of` is.
  static Abstract partOf(Abstract of) {
    return of.kind == Kind::Top ? of : Abstract{Kind::Smaller, of.param};
  }
};

// The classes of the parameters of `main`, which is on a cycle whose
// functions are `cycle`.
class Interpreter {
public:
  Interpreter(idr::FuncOp main, const llvm::DenseSet<Operation *> &cycle,
              const References &references)
      : main(main), cycle(cycle), references(references), same(main.getNumArguments(), false),
        smaller(main.getNumArguments(), false), other(main.getNumArguments(), false) {}

  SmallVector<BindingTime> run();

private:
  // A function of the cycle with abstract arguments, the first time it is
  // reached with them.
  void push(idr::FuncOp fn, ArrayRef<Abstract> args);
  void visit(idr::FuncOp fn, ArrayRef<Abstract> args);
  void refer(idr::FuncOp target, ArrayRef<Abstract> args);

  idr::FuncOp main;
  const llvm::DenseSet<Operation *> &cycle;
  const References &references;
  SmallVector<bool> same, smaller, other;
  // Each function of the cycle with the arguments it was reached with.
  std::set<std::pair<Operation *, SmallVector<unsigned>>> visited;
  SmallVector<std::pair<idr::FuncOp, SmallVector<Abstract>>> work;
};

SmallVector<BindingTime> Interpreter::run() {
  SmallVector<Abstract> identity;
  for (unsigned i = 0; i < main.getNumArguments(); ++i)
    identity.push_back(Abstract::same(i));
  push(main, identity);
  while (!work.empty() && !llvm::all_of(other, [](bool b) { return b; })) {
    auto [fn, args] = work.pop_back_val();
    visit(fn, args);
  }
  SmallVector<BindingTime> out;
  for (unsigned i = 0; i < main.getNumArguments(); ++i) {
    if (other[i] || (!same[i] && !smaller[i]))
      out.push_back(BindingTime::Other);
    else if (same[i] && smaller[i])
      out.push_back(BindingTime::Bounded);
    else
      out.push_back(same[i] ? BindingTime::Fixed : BindingTime::Decreasing);
  }
  return out;
}

void Interpreter::push(idr::FuncOp fn, ArrayRef<Abstract> args) {
  SmallVector<unsigned> codes =
      llvm::map_to_vector(args, [](const Abstract &arg) { return arg.code(); });
  if (visited.emplace(fn.getOperation(), std::move(codes)).second)
    work.emplace_back(fn, SmallVector<Abstract>(args));
}

void Interpreter::visit(idr::FuncOp fn, ArrayRef<Abstract> args) {
  llvm::DenseMap<Value, Abstract> known;
  auto eval = [&](auto &self, Value value) -> Abstract {
    if (auto it = known.find(value); it != known.end())
      return it->second;
    Abstract out;
    if (auto arg = dyn_cast<BlockArgument>(value)) {
      Operation *parent = arg.getOwner()->getParentOp();
      if (parent == fn.getOperation() && arg.getOwner()->isEntryBlock()) {
        if (arg.getArgNumber() < args.size())
          out = args[arg.getArgNumber()];
      } else if (auto match = dyn_cast<MatchOp>(parent)) {
        out = Abstract::partOf(self(self, match.getScrutinee()));
      }
    } else if (Operation *def = value.getDefiningOp()) {
      if (auto field = dyn_cast<FieldOp>(def))
        out = Abstract::partOf(self(self, field.getValue()));
      else if (auto pred = dyn_cast<BigPredOp>(def))
        out = Abstract::partOf(self(self, pred.getValue()));
      // An integer counted down by a positive step. Unlike a Nat it may
      // pass zero; specialization unrolls only a counter that stays in a
      // small range of naturals, so its clones stay few either way.
      else if (IntegerAttr step; isa<arith::SubIOp>(def) &&
                                 matchPattern(def->getOperand(1), m_Constant(&step)) &&
                                 step.getValue().isStrictlyPositive())
        out = Abstract::partOf(self(self, def->getOperand(0)));
    }
    known[value] = out;
    return out;
  };
  for (const References::Site &site : references.of(fn)) {
    idr::FuncOp target = site.target;
    if (!cycle.contains(target.getOperation()))
      continue;
    SmallVector<Abstract> passed(target.getNumArguments());
    if (auto call = dyn_cast<idr::CallOp>(site.at)) {
      for (auto [i, operand] : llvm::enumerate(call.getArgs()))
        if (i < passed.size())
          passed[i] = eval(eval, operand);
    } else if (auto closure = dyn_cast<ClosureOp>(site.at)) {
      // The captures are the leading parameters; the rest come from the
      // applies of the closure, which may pass anything.
      for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
        if (i < passed.size())
          passed[i] = eval(eval, capture);
    }
    refer(target, passed);
  }
}

void Interpreter::refer(idr::FuncOp target, ArrayRef<Abstract> args) {
  if (target == main)
    for (auto [i, arg] : llvm::enumerate(args)) {
      if (arg.kind == Abstract::Kind::Same && arg.param == i)
        same[i] = true;
      else if (arg.kind == Abstract::Kind::Smaller && arg.param == i)
        smaller[i] = true;
      else
        other[i] = true;
    }
  push(target, args);
}

// The binding time of a parameter that two recursions pass, one as `a` and
// the other as `b` says: free where one does not recur.
BindingTime join(BindingTime a, BindingTime b) {
  if (a == BindingTime::Free || a == b)
    return b;
  if (b == BindingTime::Free)
    return a;
  if (a == BindingTime::Other || b == BindingTime::Other)
    return BindingTime::Other;
  // Fixed, decreasing or bounded on each side: the parameter or a part of it.
  return BindingTime::Bounded;
}

// The callee of a raised clone's key and the arity the key counts, or none
// for another key.
std::optional<std::pair<StringAttr, unsigned>> raisedFrom(Attribute key) {
  if (auto apply = dyn_cast<KeyApplyAttr>(key))
    return std::make_pair(apply.getCallee(), apply.getArity());
  if (auto field = dyn_cast<KeyApplyFieldAttr>(key))
    return std::make_pair(field.getCallee(), field.getArity());
  return std::nullopt;
}

} // namespace

BindingTimes::BindingTimes(Operation *op, AnalysisManager &am) {
  const References &references = am.getAnalysis<References>();
  const CloneTable &clones = am.getAnalysis<CloneTable>();
  const SymbolTable &symbols = am.getAnalysis<SymbolTable>();

  // The cycles: the components that hold a recursive function.
  SmallVector<llvm::DenseSet<Operation *>> cycles;
  llvm::DenseMap<Operation *, unsigned> cycleOf;
  for (const SmallVector<idr::FuncOp> &component : references.components()) {
    if (!llvm::any_of(component, [&](idr::FuncOp fn) { return references.isRecursive(fn); }))
      continue;
    auto at = static_cast<unsigned>(cycles.size());
    llvm::DenseSet<Operation *> &cycle = cycles.emplace_back();
    for (idr::FuncOp fn : component) {
      cycle.insert(fn.getOperation());
      cycleOf[fn.getOperation()] = at;
    }
  }

  ArrayRef<idr::FuncOp> functions = references.functions();
  SmallVector<SmallVector<BindingTime>> slots(functions.size());
  mlir::parallelFor(op->getContext(), 0, functions.size(), [&](size_t i) {
    idr::FuncOp fn = functions[i];
    auto it = cycleOf.find(fn.getOperation());
    if (fn.isExternal() || it == cycleOf.end())
      slots[i].assign(fn.getNumArguments(), BindingTime::Free);
    else
      slots[i] = Interpreter(fn, cycles[it->second], references).run();
  });
  for (auto [at, slot] : llvm::enumerate(slots)) {
    idr::FuncOp fn = functions[at];
    times[fn.getSymNameAttr()] = std::move(slot);
  }

  // Raised clones, each after a raised clone it was raised from.
  llvm::DenseSet<Operation *> inherited;
  auto inherit = [&](auto &self, idr::FuncOp fn) -> void {
    if (!inherited.insert(fn.getOperation()).second)
      return;
    const Clone *clone = clones.find(fn.getSymNameAttr());
    std::optional<std::pair<StringAttr, unsigned>> from =
        clone ? raisedFrom(clone->key) : std::nullopt;
    if (!from)
      return;
    auto [name, arity] = *from;
    auto callee = symbols.lookup<idr::FuncOp>(name);
    if (!callee || callee.isExternal() || callee.getNumArguments() != arity)
      return;
    self(self, callee);
    ArrayRef<BindingTime> theirs = times.find(name)->second;
    if (llvm::all_of(theirs, [](BindingTime t) { return t == BindingTime::Free; }))
      return;
    // Parameter p of a raised clone is its callee's parameter p, then an
    // apply's argument.
    SmallVector<BindingTime> &ours = times.find(fn.getSymNameAttr())->second;
    for (unsigned p = 0; p < ours.size(); ++p)
      ours[p] = join(ours[p], p < arity ? theirs[p] : BindingTime::Other);
  };
  for (idr::FuncOp fn : functions)
    inherit(inherit, fn);
}

bool BindingTimes::isInvalidated(const AnalysisManager::PreservedAnalyses &pa) const {
  return !pa.isPreserved<BindingTimes>() || !pa.isPreserved<References>() ||
         !pa.isPreserved<CloneTable>() || !pa.isPreserved<SymbolTable>();
}

std::optional<BindingTime> BindingTimes::of(StringAttr fn, unsigned index) const {
  auto it = times.find(fn);
  if (it == times.end() || index >= it->second.size())
    return std::nullopt;
  return it->second[index];
}

ArrayRef<BindingTime> BindingTimes::of(StringAttr fn) const {
  auto it = times.find(fn);
  return it == times.end() ? ArrayRef<BindingTime>() : ArrayRef<BindingTime>(it->second);
}

} // namespace idr
