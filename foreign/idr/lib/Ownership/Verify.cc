// The owned stage's rule: each reference is consumed exactly once on every
// path. It extends the world's rule (Dialect.cc), which counts uses on the
// worst path, to exact counts: a walk of each function follows the
// references every value holds along the ops, taking the regions of a match
// as alternatives that must agree where they meet again.
//
// Runs as the verifier of the module's `idr.stage`, before the ops inside
// are verified, so it assumes no op is well formed beyond what it checks.

#include "Ownership/Ownership.h"

#include "Lower/Layout.h"

#include "llvm/ADT/DenseSet.h"

#include <optional>

using namespace mlir;

namespace idr::ownership {

namespace {

class Checker {
public:
  Checker(Counting &counting, SymbolTableCollection &symbols,
          function_ref<lower::Layouts *()> layouts)
      : counting(counting), symbols(symbols), layouts(layouts) {}

  LogicalResult check(func::FuncOp fn) {
    Block &entry = fn.getBody().front();
    for (BlockArgument arg : entry.getArguments())
      if (counting.tracked(arg)) {
        bool borrowed = isBorrowed(fn, arg.getArgNumber());
        define(arg, borrowed ? 0 : 1);
        if (borrowed)
          owners[arg] = Value();
      }
    return failure(failed(walk(entry)));
  }

private:
  // The references each value in scope holds, with an undo log so that a
  // match's regions start from the same state.
  struct Change {
    Value value;
    std::optional<int> old;
  };

  void set(Value value, int references) {
    auto it = held.find(value);
    log.push_back({value, it == held.end() ? std::nullopt : std::optional<int>(it->second)});
    held[value] = references;
  }

  void define(Value value, int references, Value owner = Value(), bool borrowed = false) {
    set(value, references);
    if (borrowed)
      owners[value] = owner;
  }

  void undo(size_t mark) {
    while (log.size() > mark) {
      Change change = log.pop_back_val();
      if (change.old)
        held[change.value] = *change.old;
      else
        held.erase(change.value);
    }
  }

  // The references of the values that were in scope at `mark` and changed
  // since.
  llvm::MapVector<Value, int> changesSince(size_t mark) {
    llvm::MapVector<Value, int> changes;
    llvm::DenseSet<Value> seen;
    for (size_t i = mark; i < log.size(); ++i) {
      if (!seen.insert(log[i].value).second || !log[i].old)
        continue;
      changes[log[i].value] = held.lookup(log[i].value);
    }
    return changes;
  }

  // Whether `value` may be used here: it holds a reference, or what it was
  // read from is alive, or it is a borrowed parameter.
  bool alive(Value value) {
    for (unsigned depth = 0; depth < 1024; ++depth) {
      if (!counting.tracked(value))
        return true;
      auto it = held.find(value);
      if (it != held.end() && it->second > 0)
        return true;
      auto owner = owners.find(value);
      if (owner == owners.end())
        return false;
      if (!owner->second)
        return true;
      value = owner->second;
    }
    return false;
  }

  InFlightDiagnostic fail(Operation &op, Value value, const Twine &what) {
    InFlightDiagnostic diag = op.emitOpError(what);
    diag.attachNote(value.getLoc()) << "the value is defined here";
    return diag;
  }

  LogicalResult consume(Operation &op, Value value) {
    if (!counting.tracked(value))
      return success();
    int references = held.lookup(value);
    if (references < 1)
      return fail(op, value,
                  "consumes a reference that the value does not hold here: it was consumed "
                  "before on this path, or it is borrowed and needs an idr.inc");
    set(value, references - 1);
    return success();
  }

  LogicalResult use(Operation &op, Value value) {
    if (counting.tracked(value) && !alive(value))
      return fail(op, value, "uses a value whose last reference is gone on this path");
    return success();
  }

  // Every value `block` defines holds no reference at its end.
  LogicalResult settled(Block &block, Operation &at) {
    auto check = [&](Value value) -> LogicalResult {
      if (counting.tracked(value) && held.lookup(value) != 0)
        return fail(at, value, "ends a path on which a value still holds a reference");
      return success();
    };
    for (BlockArgument arg : block.getArguments())
      if (failed(check(arg)))
        return failure();
    for (Operation &op : block)
      for (Value result : op.getResults())
        if (failed(check(result)))
          return failure();
    return success();
  }

  // Walks `block` from the current state. Returns whether its end is
  // reached, or failure after reporting a violation.
  FailureOr<bool> walk(Block &block) {
    for (Operation &op : block) {
      if (isa<ub::UnreachableOp>(op))
        return false;
      if (op.getNumRegions() != 0) {
        FailureOr<bool> reached = walkRegions(op);
        if (failed(reached) || !*reached)
          return reached;
        continue;
      }
      if (failed(visit(op)))
        return failure();
      if (isa<func::ReturnOp>(op)) {
        for (auto &[value, references] : held)
          if (references != 0)
            return fail(op, value, "returns while a value still holds a reference");
        return true;
      }
    }
    return true;
  }

  LogicalResult visit(Operation &op) {
    if (auto inc = dyn_cast<IncOp>(op)) {
      Value value = inc.getValue();
      if (!counting.tracked(value))
        return success();
      if (!alive(value))
        return fail(op, value, "adds a reference to a value whose last reference is gone");
      set(value, held.lookup(value) + 1);
      return success();
    }
    if (auto select = dyn_cast<arith::SelectOp>(op); select && counting.tracked(select))
      return op.emitOpError("selects between values that hold references; in the owned "
                            "stage a match does");
    // What the op borrows must be alive for all of it, after what it
    // consumes.
    SmallVector<Value> borrowed;
    for (OpOperand &operand : op.getOpOperands()) {
      if (!counting.tracked(operand.get()))
        continue;
      if (useKind(operand) == Use::Consume) {
        if (failed(consume(op, operand.get())))
          return failure();
      } else {
        borrowed.push_back(operand.get());
      }
    }
    for (Value value : borrowed)
      if (failed(use(op, value)))
        return failure();
    for (Value result : op.getResults()) {
      if (!counting.tracked(result))
        continue;
      if (isa<FieldOp>(op))
        define(result, 0, op.getOperand(0), /*borrowed=*/true);
      else
        define(result, 1);
    }
    if (auto reuse = dyn_cast<ReuseOp>(op))
      return fits(reuse);
    return success();
  }

  // What a use does, where a loop's terminator passes on a borrowed slot.
  Use useKind(OpOperand &operand) {
    Operation *op = operand.getOwner();
    Operation *loop = op->getParentOp();
    if (isa_and_nonnull<scf::WhileOp, scf::ForOp>(loop) && isa<scf::ConditionOp, scf::YieldOp>(op)) {
      unsigned slot = operand.getOperandNumber() - (isa<scf::ConditionOp>(op) ? 1 : 0);
      if (Value owner = slotOwner(loop, slot))
        return Use::Borrow;
    }
    if (isa<YieldOp>(op) && op->getParentOp() &&
        passedOn.count(op->getParentOp()->getResult(operand.getOperandNumber())))
      return Use::Borrow;
    return useOf(operand, symbols);
  }

  // The borrowed value a slot of a loop carries on its first iteration, or
  // null when the slot is owned.
  Value slotOwner(Operation *loop, unsigned slot) {
    auto it = loops.find(loop);
    if (it == loops.end() || slot >= it->second.size())
      return Value();
    return it->second[slot];
  }

  // The token of an idr.reuse comes from an idr.reset of a cell of the
  // same size.
  LogicalResult fits(ReuseOp reuse) {
    Operation *made = reuse.getToken().getDefiningOp();
    SymbolRefAttr cell = made ? made->getAttrOfType<SymbolRefAttr>("ctor") : nullptr;
    if (!isa_and_nonnull<ResetOp, TakeOp>(made) || !cell)
      return reuse.emitOpError("builds in a token that no idr.reset or idr.take made");
    CtorOp from = lookupCtor(made, cell);
    CtorOp to = lookupCtor(reuse, reuse.getCtor());
    if (!from || !to)
      return success();
    // Without layouts, which say why, there is nothing to compare.
    lower::Layouts *cells = layouts();
    if (!cells)
      return failure();
    unsigned have = cells->box(from).size, need = cells->box(to).size;
    if (have != need)
      return reuse.emitOpError("builds a cell of ")
             << need << " bytes in the " << have << "-byte cell of " << cell;
    return success();
  }

  FailureOr<bool> walkRegions(Operation &op) {
    if (auto match = dyn_cast<MatchOp>(op))
      return walkMatch(op, match.getScrutinee());
    if (auto match = dyn_cast<MatchLitOp>(op))
      return walkMatch(op, match.getScrutinee());
    if (auto loop = dyn_cast<scf::WhileOp>(op))
      return walkLoop(loop);
    if (auto loop = dyn_cast<scf::ForOp>(op))
      return walkFor(loop);
    return op.emitOpError("has regions, which the owned stage does not know how to count");
  }

  // Each region starts from the state before the match; the regions that
  // reach their yield must leave every value from outside with the same
  // references, which it then holds after the match.
  FailureOr<bool> walkMatch(Operation &op, Value scrutinee) {
    if (failed(use(op, scrutinee)))
      return failure();
    size_t mark = log.size();
    SmallVector<llvm::MapVector<Value, int>> ends;
    for (Region &region : op.getRegions()) {
      if (region.empty())
        continue;
      Block &block = region.front();
      for (BlockArgument field : block.getArguments())
        if (counting.tracked(field))
          define(field, 0, scrutinee, /*borrowed=*/true);
      FailureOr<bool> reached = walk(block);
      if (failed(reached))
        return failure();
      if (*reached) {
        if (failed(settled(block, block.back())))
          return failure();
        ends.push_back(changesSince(mark));
      }
      undo(mark);
    }
    if (ends.empty())
      return false;
    llvm::MapVector<Value, int> after;
    for (auto &end : ends)
      for (auto &[value, references] : end)
        after.try_emplace(value, references);
    for (auto &[value, references] : after)
      for (auto &end : ends) {
        auto it = end.find(value);
        int here = it == end.end() ? held.lookup(value) : it->second;
        if (here != references)
          return fail(op, value, "leaves a value with ")
                 << references << " references on one path and " << here << " on another";
      }
    for (auto &[value, references] : after)
      set(value, references);
    for (Value result : op.getResults()) {
      if (!counting.tracked(result))
        continue;
      auto it = passedOn.find(result);
      if (it != passedOn.end())
        define(result, 0, it->second, /*borrowed=*/true);
      else
        define(result, 1);
    }
    return true;
  }

  // A borrowed slot's value reaches the loop's scf.condition through the
  // matches idr-tail-loops builds on the way, which pass it on borrowed.
  void passOn(Value value, Value owner) {
    auto result = dyn_cast<OpResult>(value);
    if (!result || !isa<MatchOp, MatchLitOp>(result.getOwner()))
      return;
    passedOn[value] = owner;
    for (Region &region : result.getOwner()->getRegions())
      if (!region.empty())
        if (auto yield = dyn_cast<YieldOp>(region.front().getTerminator()))
          passOn(yield.getOperand(result.getResultNumber()), owner);
  }

  // An scf.while of idr-tail-loops, which carries a function's parameters
  // first, then its results. A slot whose first value is borrowed (a
  // borrowed parameter) carries borrowed values, which live as long as that
  // first one; every other slot's values are owned: the initial values are
  // consumed, each region takes its arguments owned and consumes what its
  // terminator passes on, and leaves the values from outside as it found
  // them. The results and the after region's arguments that nothing uses
  // are the payload of the path not taken, which is poison there.
  FailureOr<bool> walkLoop(scf::WhileOp loop) {
    Operation &op = *loop.getOperation();
    SmallVector<Value> &slots = loops[loop];
    for (Value init : loop.getInits()) {
      bool borrowed = counting.tracked(init) && held.lookup(init) == 0 && alive(init);
      slots.push_back(borrowed ? init : Value());
      if (failed(borrowed ? use(op, init) : consume(op, init)))
        return failure();
    }
    if (!loop.getBefore().empty())
      if (auto condition = dyn_cast<scf::ConditionOp>(loop.getBefore().front().getTerminator()))
        for (auto [slot, value] : llvm::enumerate(condition.getArgs()))
          if (Value owner = slotOwner(loop, static_cast<unsigned>(slot)))
            passOn(value, owner);
    auto slotType = [&](unsigned slot, Value value, bool after) {
      if (Value owner = slotOwner(loop, slot))
        define(value, 0, owner, /*borrowed=*/true);
      else
        define(value, after && value.use_empty() ? 0 : 1);
    };
    size_t mark = log.size();
    bool exits = false;
    for (Region *region : {&loop.getBefore(), &loop.getAfter()}) {
      if (region->empty())
        continue;
      Block &block = region->front();
      bool after = region == &loop.getAfter();
      for (BlockArgument arg : block.getArguments())
        if (counting.tracked(arg))
          slotType(arg.getArgNumber(), arg, after);
      FailureOr<bool> reached = walk(block);
      if (failed(reached))
        return failure();
      if (*reached) {
        if (failed(settled(block, block.back())))
          return failure();
        auto changes = changesSince(mark);
        if (!changes.empty())
          return fail(op, changes.front().first,
                      "changes the references of a value from outside the loop in its body");
        exits = exits || !after;
      }
      undo(mark);
    }
    for (OpResult result : loop.getResults())
      if (counting.tracked(result))
        slotType(result.getResultNumber(), result, /*after=*/true);
    return exits;
  }

  // An scf.for that idr-tail-loops made of a counted scf.while: its slots
  // are the iteration arguments, borrowed or owned as a while loop's, and
  // its body is the after region, which always reaches its yield or ends
  // the program.
  FailureOr<bool> walkFor(scf::ForOp loop) {
    Operation &op = *loop.getOperation();
    for (Value bound : {loop.getLowerBound(), loop.getUpperBound(), loop.getStep()})
      if (failed(use(op, bound)))
        return failure();
    SmallVector<Value> &slots = loops[loop];
    for (Value init : loop.getInitArgs()) {
      bool borrowed = counting.tracked(init) && held.lookup(init) == 0 && alive(init);
      slots.push_back(borrowed ? init : Value());
      if (failed(borrowed ? use(op, init) : consume(op, init)))
        return failure();
    }
    auto slotType = [&](unsigned slot, Value value, bool result) {
      if (Value owner = slotOwner(loop, slot))
        define(value, 0, owner, /*borrowed=*/true);
      else
        define(value, result && value.use_empty() ? 0 : 1);
    };
    size_t mark = log.size();
    Block &body = *loop.getBody();
    for (BlockArgument arg : loop.getRegionIterArgs())
      if (counting.tracked(arg))
        slotType(arg.getArgNumber() - loop.getNumInductionVars(), arg, /*result=*/false);
    FailureOr<bool> reached = walk(body);
    if (failed(reached))
      return failure();
    if (*reached) {
      if (failed(settled(body, body.back())))
        return failure();
      auto changes = changesSince(mark);
      if (!changes.empty())
        return fail(op, changes.front().first,
                    "changes the references of a value from outside the loop in its body");
    }
    undo(mark);
    for (OpResult result : loop.getResults())
      if (counting.tracked(result))
        slotType(result.getResultNumber(), result, /*result=*/true);
    return true;
  }

  Counting &counting;
  SymbolTableCollection &symbols;
  function_ref<lower::Layouts *()> layouts;
  llvm::DenseMap<Value, int> held;
  llvm::DenseMap<Value, Value> owners;
  SmallVector<Change> log;
  // For each loop, the owner of each borrowed slot.
  llvm::DenseMap<Operation *, SmallVector<Value>> loops;
  // The match results that pass a borrowed slot on, with its owner.
  llvm::DenseMap<Value, Value> passedOn;
};

} // namespace

LogicalResult verifyOwned(ModuleOp module) {
  Counting counting(module);
  SymbolTableCollection symbols;
  // Only a reuse needs the sizes of cells.
  std::optional<FailureOr<lower::Layouts>> cells;
  auto layouts = [&]() -> lower::Layouts * {
    if (!cells)
      cells.emplace(lower::Layouts::of(module));
    return succeeded(*cells) ? &**cells : nullptr;
  };
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal())
      continue;
    Checker checker(counting, symbols, layouts);
    if (failed(checker.check(fn)))
      return failure();
  }
  return success();
}

} // namespace idr::ownership
