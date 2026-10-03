// idr.specialize:interpreter: the abstract interpretation of a cycle of
// references, for the binding times of one function's parameters, which
// only BindingTimes runs. Nothing here is exported.
export module idr.specialize:interpreter;

import idr.mlir;
import idr.dialect;

import :bindingtime;
import :foreachreference;

using namespace mlir;

namespace idr::specialize {

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
  Interpreter(mlir::func::FuncOp main, const llvm::DenseSet<mlir::Operation *> &cycle,
              mlir::SymbolTable &symbols);

  llvm::SmallVector<BindingTime> run();

private:
  // A function of the cycle with abstract arguments, the first time it is
  // reached with them.
  void push(mlir::func::FuncOp fn, llvm::ArrayRef<Abstract> args);
  void visit(mlir::func::FuncOp fn, llvm::ArrayRef<Abstract> args);
  void refer(mlir::func::FuncOp target, llvm::ArrayRef<Abstract> args);

  mlir::func::FuncOp main;
  const llvm::DenseSet<mlir::Operation *> &cycle;
  mlir::SymbolTable &symbols;
  llvm::SmallVector<bool> same, smaller, other;
  llvm::StringSet<> visited;
  llvm::SmallVector<std::pair<mlir::func::FuncOp, llvm::SmallVector<Abstract>>> work;
};

Interpreter::Interpreter(func::FuncOp main, const llvm::DenseSet<Operation *> &cycle,
                         SymbolTable &symbols)
    : main(main), cycle(cycle), symbols(symbols), same(main.getNumArguments(), false),
      smaller(main.getNumArguments(), false), other(main.getNumArguments(), false) {}

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

void Interpreter::push(func::FuncOp fn, ArrayRef<Abstract> args) {
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

void Interpreter::visit(func::FuncOp fn, ArrayRef<Abstract> args) {
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

void Interpreter::refer(func::FuncOp target, ArrayRef<Abstract> args) {
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

} // namespace idr::specialize
