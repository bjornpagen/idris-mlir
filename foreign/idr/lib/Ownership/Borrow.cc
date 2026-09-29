// Borrow inference (Counting Immutable Beans §4.2, as Lean's
// Compiler/IR/Borrow.lean does it): a parameter the function never needs a
// reference of its own for is borrowed, and its callers keep the
// reference, which saves an idr.inc and an idr.dec per call.
//
// Every parameter starts borrowed and becomes owned, until nothing changes
// in the module, when it or a field read from it
//   - is reset (its cell is reused only if it is owned);
//   - is passed to an owned parameter of a call;
//   - is itself stored in a constructor or a closure, or passed to the
//     function of a closure, which takes every argument owned;
// and when an owned value is passed to it by a tail call from the same
// cycle of calls, which would otherwise have to drop its reference after
// the call, so that the call would no longer be a tail call.
// The public root, and every function a closure names, keep their
// parameters owned: their callers are not calls this pass sees. A
// parameter of quantity 1 is owned too: Idris proved the function uses it
// once, so it moves to that use and is never counted.

#include "Ownership/Ownership.h"

#include "Passes/Scc.h"

#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::ownership {

namespace {

// The quantity Idris gave the parameter. It moves into the type (a linear
// value's own type) once the frontend emits one; this is its one reader.
bool isLinear(func::FuncOp fn, unsigned index) {
  auto quantity = fn.getArgAttrOfType<StringAttr>(index, "idr.quantity");
  return quantity && quantity.getValue() == "1";
}

class Inference {
public:
  Inference(ModuleOp module, Counting &counting) : module(module), counting(counting) {}

  unsigned run() {
    llvm::DenseSet<Attribute> named;
    module.walk([&](Operation *op) {
      if (auto closure = dyn_cast<ClosureOp>(op))
        named.insert(closure.getCalleeAttr().getAttr());
      op->getAttrDictionary().walk(
          [&](ClosureAttr closure) { named.insert(closure.getCallee().getAttr()); });
    });
    for (auto fn : module.getOps<func::FuncOp>()) {
      if (fn.isExternal())
        continue;
      functions.push_back(fn);
      bool fixed = fn.isPublic() || named.contains(fn.getSymNameAttr());
      SmallVector<bool> params;
      for (auto [index, type] : llvm::enumerate(fn.getArgumentTypes()))
        params.push_back(fixed || !counting.counted(type) ||
                         isLinear(fn, static_cast<unsigned>(index)));
      owned[fn] = std::move(params);
    }
    findCycles();
    do {
      changed = false;
      for (func::FuncOp fn : functions)
        collect(fn);
    } while (changed);
    unsigned borrowed = 0;
    for (func::FuncOp fn : functions)
      for (auto [index, isOwned] : llvm::enumerate(owned[fn])) {
        auto param = static_cast<unsigned>(index);
        if (isOwned) {
          fn.removeArgAttr(param, borrowedAttr);
          continue;
        }
        fn.setArgAttr(param, borrowedAttr, UnitAttr::get(module.getContext()));
        ++borrowed;
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
    auto components = passes::stronglyConnected<func::FuncOp>(functions, calls);
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

  // Whether the results of `op` are the results of the function: it is
  // followed by a terminator that passes them on, a return or the yield
  // of a match whose own results are.
  static bool inTailPosition(Operation *op) {
    Operation *next = op->getNextNode();
    if (!next || !next->hasTrait<OpTrait::IsTerminator>() ||
        !llvm::equal(next->getOperands(), op->getResults()))
      return false;
    if (isa<func::ReturnOp>(next))
      return true;
    if (!isa<YieldOp>(next))
      return false;
    Operation *match = next->getParentOp();
    return isa<MatchOp, MatchLitOp>(match) && inTailPosition(match);
  }

  void collect(func::FuncOp fn) {
    current = fn;
    ownedFields.clear();
    fn.walk([&](Operation *op) {
      if (auto reset = dyn_cast<ResetOp>(op)) {
        own(reset.getValue());
      } else if (auto call = dyn_cast<func::CallOp>(op)) {
        func::FuncOp g = callee(call, symbols);
        auto it = g ? owned.find(g) : owned.end();
        for (auto [index, arg] : llvm::enumerate(call.getOperands()))
          if (it == owned.end() || index >= it->second.size() || it->second[index])
            own(arg);
        if (it != owned.end() && cycleOf.lookup(g) == cycleOf.lookup(fn) && inTailPosition(call))
          for (auto [index, arg] : llvm::enumerate(call.getOperands()))
            if (isOwned(arg))
              ownParam(g, static_cast<unsigned>(index));
      } else if (auto apply = dyn_cast<ApplyOp>(op)) {
        for (Value arg : apply.getArgs())
          ownIfParam(arg);
      } else if (isa<ConOp, ClosureOp, ReuseOp>(op)) {
        for (Value operand : op->getOperands())
          ownIfParam(operand);
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

unsigned inferBorrows(ModuleOp module, Counting &counting) {
  return Inference(module, counting).run();
}

} // namespace idr::ownership
