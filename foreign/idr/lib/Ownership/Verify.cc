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
          function_ref<lower::Layouts &()> layouts)
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
      if (useOf(operand, symbols) == Use::Consume) {
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

  // The token of an idr.reuse comes from an idr.reset of a cell of the
  // same size.
  LogicalResult fits(ReuseOp reuse) {
    auto reset = reuse.getToken().getDefiningOp<ResetOp>();
    if (!reset)
      return reuse.emitOpError("builds in a token that no idr.reset made");
    CtorOp from = lookupCtor(reset, reset.getCtor());
    CtorOp to = lookupCtor(reuse, reuse.getCtor());
    if (!from || !to)
      return success();
    unsigned have = layouts().box(from).size, need = layouts().box(to).size;
    if (have != need)
      return reuse.emitOpError("builds a cell of ")
             << need << " bytes in the " << have << "-byte cell of " << reset.getCtor();
    return success();
  }

  FailureOr<bool> walkRegions(Operation &op) {
    if (auto match = dyn_cast<MatchOp>(op))
      return walkMatch(op, match.getScrutinee());
    if (auto match = dyn_cast<MatchLitOp>(op))
      return walkMatch(op, match.getScrutinee());
    if (auto loop = dyn_cast<scf::WhileOp>(op))
      return walkLoop(loop);
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
    for (Value result : op.getResults())
      if (counting.tracked(result))
        define(result, 1);
    return true;
  }

  // An scf.while of idr-tail-loops: the initial values are consumed, and
  // each region takes its arguments owned and consumes what its terminator
  // passes on, leaving the values from outside as it found them. The
  // results and the after region's arguments that nothing uses are the
  // payload of the path not taken, which is poison there.
  FailureOr<bool> walkLoop(scf::WhileOp loop) {
    Operation &op = *loop.getOperation();
    for (Value init : loop.getInits())
      if (failed(consume(op, init)))
        return failure();
    size_t mark = log.size();
    bool exits = false;
    for (Region *region : {&loop.getBefore(), &loop.getAfter()}) {
      if (region->empty())
        continue;
      Block &block = region->front();
      bool after = region == &loop.getAfter();
      for (BlockArgument arg : block.getArguments())
        if (counting.tracked(arg))
          define(arg, after && arg.use_empty() ? 0 : 1);
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
    for (Value result : loop.getResults())
      if (counting.tracked(result))
        define(result, result.use_empty() ? 0 : 1);
    return exits;
  }

  Counting &counting;
  SymbolTableCollection &symbols;
  function_ref<lower::Layouts &()> layouts;
  llvm::DenseMap<Value, int> held;
  llvm::DenseMap<Value, Value> owners;
  SmallVector<Change> log;
};

} // namespace

LogicalResult verifyOwned(ModuleOp module) {
  Counting counting(module);
  SymbolTableCollection symbols;
  // Only a reuse needs the sizes of cells.
  std::optional<lower::Layouts> cells;
  auto layouts = [&]() -> lower::Layouts & {
    if (!cells)
      cells.emplace(module);
    return *cells;
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
