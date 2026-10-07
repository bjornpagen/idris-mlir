// idr.ownership:borrow: borrow inference (Counting Immutable Beans §4.2,
// as Lean's Compiler/IR/Borrow.lean does it): a parameter the function
// never needs a reference of its own for is borrowed, and its callers keep
// the reference, which saves an idr.dup and an idr.drop per call.
//
// Every parameter starts borrowed and becomes owned, until nothing changes
// in the module, when it or a field read from it
//   - is taken apart (its cell is reused only if it is owned);
//   - is passed to an owned parameter of a call;
//   - is itself stored in a constructor or a closure, or passed to the
//     function of a closure, which takes every argument owned;
//   - is returned, or yielded by a match, whose results are owned;
// and when an owned value is passed to it by a tail call from the same
// cycle of calls, which would otherwise have to drop its reference after
// the call, so that the call would no longer be a tail call. A self call
// whose result a tail position puts in a constructor counts as one:
// idr-trmc makes it a tail call that writes the field, unless a drop sits
// between the call and the constructor.
// The public root, and every function a closure names, keep their
// parameters owned: their callers are not calls this pass sees. A
// parameter of quantity 1 is owned too: Idris proved the function uses it
// once, so it moves to that use and is never counted.
//
// The answer is written into the signatures: an owned parameter and
// every result that holds references are owned (`!idr.own<T>`), a
// borrowed parameter keeps its plain type, a view of the caller's value.
export module idr.ownership:borrow;

import idr.mlir;
import idr.dialect;
import idr.graph;

import :callee;
import :counting;
import :readfrom;

using namespace mlir;

namespace idr::ownership {

namespace {

class Inference {
public:
  Inference(ModuleOp module, Counting &counting) : module(module), counting(counting) {}

  unsigned run() {
    llvm::DenseSet<Attribute> named;
    module.walk([&](Operation *op) {
      if (auto closure = dyn_cast<ClosureOp>(op))
        named.insert(closure.getCalleeAttr().getAttr());
      if (auto suspend = dyn_cast<SuspendOp>(op))
        named.insert(suspend.getCalleeAttr().getAttr());
      op->getAttrDictionary().walk(
          [&](ClosureAttr closure) { named.insert(closure.getCallee().getAttr()); });
    });
    for (auto fn : module.getOps<func::FuncOp>()) {
      if (fn.isExternal())
        continue;
      functions.push_back(fn);
      bool fixed = fn.isPublic() || named.contains(fn.getSymNameAttr());
      SmallVector<bool> params;
      for (Type type : fn.getArgumentTypes())
        params.push_back(fixed || !counting.counted(type) || quantityOf(type) == Quantity::One);
      owned[fn] = std::move(params);
    }
    findCycles();
    do {
      changed = false;
      for (func::FuncOp fn : functions)
        collect(fn);
    } while (changed);
    unsigned borrowed = 0;
    for (func::FuncOp fn : functions) {
      SmallVector<Type> params(fn.getArgumentTypes());
      for (auto [index, holds] : llvm::enumerate(owned[fn])) {
        auto param = static_cast<unsigned>(index);
        if (!counting.counted(params[param]))
          continue;
        if (!holds) {
          ++borrowed;
          continue;
        }
        params[param] = idr::owned(params[param]);
        fn.getArgument(param).setType(params[param]);
      }
      SmallVector<Type> results;
      for (Type result : fn.getResultTypes())
        results.push_back(counting.counted(result) ? idr::owned(result) : result);
      fn.setFunctionType(FunctionType::get(module.getContext(), params, results));
    }
    return borrowed;
  }

private:
  // The cycles of calls, for the tail calls to keep.
  void findCycles() {
    auto calls = [&](func::FuncOp fn) {
      SmallVector<func::FuncOp> callees;
      fn.walk([&](func::CallOp call) {
        if (func::FuncOp g = callee(call, symbols))
          callees.push_back(g);
      });
      return callees;
    };
    auto components = graph::stronglyConnected<func::FuncOp>(functions, calls);
    for (auto [index, component] : llvm::enumerate(components))
      for (func::FuncOp fn : component)
        cycleOf[fn] = static_cast<unsigned>(index);
  }

  // The parameter `value` is of the function being collected, if it is one.
  std::optional<unsigned> paramIndex(Value value) {
    auto arg = dyn_cast<BlockArgument>(value);
    if (!arg || arg.getOwner()->getParentOp() != current.getOperation())
      return std::nullopt;
    return arg.getArgNumber();
  }

  void ownParam(func::FuncOp fn, unsigned index) {
    SmallVector<bool> &params = owned[fn];
    if (index < params.size() && !params[index]) {
      params[index] = true;
      changed = true;
    }
  }

  // `value` needs a reference of its own.
  void own(Value value) {
    if (!counting.tracked(value))
      return;
    if (std::optional<unsigned> index = paramIndex(value)) {
      ownParam(current, *index);
      return;
    }
    if (Value from = readFrom(value)) {
      if (ownedFields.insert(value).second)
        own(from);
    }
  }

  void ownIfParam(Value value) {
    if (paramIndex(value) && counting.tracked(value))
      own(value);
  }

  // Whether `value` holds a reference of its own in the function.
  bool isOwned(Value value) {
    if (!counting.tracked(value))
      return false;
    if (std::optional<unsigned> index = paramIndex(value))
      return owned[current][*index];
    if (Value from = readFrom(value))
      return ownedFields.contains(value) || isOwned(from);
    return true;
  }

  void collect(func::FuncOp fn) {
    current = fn;
    ownedFields.clear();
    fn.walk([&](Operation *op) {
      if (isa<TakeOp>(op)) {
        own(op->getOperand(0));
      } else if (auto call = dyn_cast<func::CallOp>(op)) {
        func::FuncOp g = callee(call, symbols);
        auto it = g ? owned.find(g) : owned.end();
        for (auto [index, arg] : llvm::enumerate(call.getOperands()))
          if (it == owned.end() || index >= it->second.size() || it->second[index])
            own(arg);
        if (it != owned.end() && cycleOf.lookup(g) == cycleOf.lookup(fn) &&
            (graph::inTailPosition(call) || graph::inTailPositionModuloConstructor(call)))
          for (auto [index, arg] : llvm::enumerate(call.getOperands()))
            if (isOwned(arg))
              ownParam(g, static_cast<unsigned>(index));
      } else if (auto apply = dyn_cast<ApplyOp>(op)) {
        for (Value arg : apply.getArgs())
          ownIfParam(arg);
      } else if (isa<ConOp, ClosureOp, SuspendOp, ReuseOp>(op)) {
        for (Value operand : op->getOperands())
          ownIfParam(operand);
      } else if (isa<func::ReturnOp, YieldOp>(op)) {
        // Borrowed, a returned parameter would need a reference of its own
        // to leave the call with, and the caller's value would be shared
        // from then on.
        for (Value operand : op->getOperands())
          own(operand);
      }
    });
  }

  ModuleOp module;
  Counting &counting;
  SymbolTableCollection symbols;
  SmallVector<func::FuncOp> functions;
  llvm::DenseMap<func::FuncOp, SmallVector<bool>> owned;
  llvm::DenseMap<func::FuncOp, unsigned> cycleOf;
  func::FuncOp current;
  llvm::DenseSet<Value> ownedFields;
  bool changed = false;
};

} // namespace

// Lean's borrow inference: which parameters of the module's functions can
// be borrowed. Writes the signatures: a borrowed parameter keeps its plain
// type, an owned one and every result that holds references become owned.
// Returns how many parameters are borrowed.
export unsigned inferBorrows(ModuleOp module, Counting &counting) {
  return Inference(module, counting).run();
}

} // namespace idr::ownership
