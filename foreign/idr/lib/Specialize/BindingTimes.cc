// Binding times, by abstract interpretation over each cycle of references.

#include "Specialize/BindingTimes.h"

#include "Passes/Scc.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/StringSet.h"

#include <string>
#include <utility>

using namespace mlir;

namespace idr::specialize {

namespace {

// Calls `refer(target, op)` for each function the body of `fn` refers to:
// the callee of a call, the label of a closure, and the label of each
// closure constant, in op order.
void forEachReference(func::FuncOp fn, SymbolTable &symbols,
                      llvm::function_ref<void(func::FuncOp, Operation *)> refer) {
  fn.getBody().walk([&](Operation *op) {
    if (auto call = dyn_cast<func::CallOp>(op)) {
      if (auto target = symbols.lookup<func::FuncOp>(call.getCalleeAttr().getAttr()))
        refer(target, op);
      return;
    }
    if (auto closure = dyn_cast<ClosureOp>(op)) {
      if (auto target = symbols.lookup<func::FuncOp>(closure.getCalleeAttr().getAttr()))
        refer(target, op);
      return;
    }
    op->getAttrDictionary().walk([&](ClosureAttr closure) {
      if (auto target = symbols.lookup<func::FuncOp>(closure.getCallee().getAttr()))
        refer(target, op);
    });
  });
}

// What a value is, in terms of the parameters of the function analyzed.
struct Abstract {
  enum class Kind : uint8_t { Top, Same, Smaller };
  Kind kind = Kind::Top;
  unsigned param = 0;

  static Abstract same(unsigned param) { return {Kind::Same, param}; }
  // A proper part of what `of` is.
  static Abstract partOf(Abstract of) {
    return of.kind == Kind::Top ? of : Abstract{Kind::Smaller, of.param};
  }
};

// The classes of the parameters of `main`, which is on a cycle whose
// functions are `cycle`.
class Interpreter {
public:
  Interpreter(func::FuncOp main, const llvm::DenseSet<Operation *> &cycle, SymbolTable &symbols)
      : main(main), cycle(cycle), symbols(symbols), same(main.getNumArguments(), false),
        smaller(main.getNumArguments(), false), other(main.getNumArguments(), false) {}

  SmallVector<BindingTime> run() {
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

private:
  // A function of the cycle with abstract arguments, the first time it is
  // reached with them.
  void push(func::FuncOp fn, ArrayRef<Abstract> args) {
    std::string key = std::to_string(reinterpret_cast<uintptr_t>(fn.getOperation()));
    for (const Abstract &arg : args) {
      key += ':';
      key += std::to_string(static_cast<unsigned>(arg.kind));
      key += '.';
      key += std::to_string(arg.kind == Abstract::Kind::Top ? 0 : arg.param);
    }
    if (visited.insert(key).second)
      work.emplace_back(fn, SmallVector<Abstract>(args));
  }

  void visit(func::FuncOp fn, ArrayRef<Abstract> args) {
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
      }
      known[value] = out;
      return out;
    };
    forEachReference(fn, symbols, [&](func::FuncOp target, Operation *op) {
      if (!cycle.contains(target.getOperation()))
        return;
      SmallVector<Abstract> passed(target.getNumArguments());
      if (auto call = dyn_cast<func::CallOp>(op)) {
        for (auto [i, operand] : llvm::enumerate(call.getOperands()))
          if (i < passed.size())
            passed[i] = eval(eval, operand);
      } else if (auto closure = dyn_cast<ClosureOp>(op)) {
        // The captures are the leading parameters; the rest come from the
        // applies of the closure, which may pass anything.
        for (auto [i, capture] : llvm::enumerate(closure.getCaptures()))
          if (i < passed.size())
            passed[i] = eval(eval, capture);
      }
      refer(target, passed);
    });
  }

  void refer(func::FuncOp target, ArrayRef<Abstract> args) {
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

  func::FuncOp main;
  const llvm::DenseSet<Operation *> &cycle;
  SymbolTable &symbols;
  llvm::SmallVector<bool> same, smaller, other;
  llvm::StringSet<> visited;
  SmallVector<std::pair<func::FuncOp, SmallVector<Abstract>>> work;
};

} // namespace

StringRef nameOf(BindingTime time) {
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
  return "other";
}

BindingTimes::BindingTimes(ModuleOp module, SymbolTable &symbols) {
  SmallVector<func::FuncOp> functions;
  for (auto fn : module.getOps<func::FuncOp>()) {
    times[fn.getOperation()].assign(fn.getNumArguments(), BindingTime::Free);
    if (!fn.isExternal())
      functions.push_back(fn);
  }
  llvm::DenseMap<func::FuncOp, SmallVector<func::FuncOp>> references;
  for (func::FuncOp fn : functions) {
    SmallVector<func::FuncOp> &out = references[fn];
    forEachReference(fn, symbols, [&](func::FuncOp target, Operation *) {
      if (!llvm::is_contained(out, target))
        out.push_back(target);
    });
  }
  for (const SmallVector<func::FuncOp> &component : idr::passes::stronglyConnected<func::FuncOp>(
           functions, [&](func::FuncOp fn) { return references.lookup(fn); })) {
    func::FuncOp first = component.front();
    if (component.size() == 1 && !llvm::is_contained(references.lookup(first), first))
      continue;
    llvm::DenseSet<Operation *> cycle;
    for (func::FuncOp fn : component)
      cycle.insert(fn.getOperation());
    for (func::FuncOp fn : component)
      times[fn.getOperation()] = Interpreter(fn, cycle, symbols).run();
  }
}

std::optional<BindingTime> BindingTimes::of(func::FuncOp fn, unsigned index) const {
  auto it = times.find(fn.getOperation());
  if (it == times.end())
    return std::nullopt;
  return it->second[index];
}

} // namespace idr::specialize
