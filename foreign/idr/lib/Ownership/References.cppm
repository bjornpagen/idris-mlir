// idr.ownership:references: the references each value in scope holds, as
// the walk of a function in the owned stage follows them. Nothing here is
// exported: the owned stage's checker is built on it.
export module idr.ownership:references;

import idr.mlir;
import idr.dialect;

import :counting;
import :isstatic;

using namespace mlir;

namespace idr::ownership {

class References {
public:
  explicit References(Counting &counting) : counting(counting) {}

protected:
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

  // Whether `value` holds a reference the walk follows: it is owned, and
  // not a value that stands for one without holding it (poison, a pending
  // field, a small big).
  bool tracked(Value value) { return isOwned(value.getType()) && !isStatic(value); }

  // The owned value a view was read from: through views, fields (idr.field,
  // the fields a match's region binds) and changes of quantity.
  static Value viewRoot(Value value) {
    for (;;) {
      if (auto arg = dyn_cast<BlockArgument>(value)) {
        auto match = dyn_cast<MatchOp>(arg.getOwner()->getParentOp());
        if (!match)
          return value;
        value = match.getScrutinee();
        continue;
      }
      Operation *def = value.getDefiningOp();
      if (!isa_and_nonnull<BorrowOp, FieldOp, LinEnterOp, LinUseOp>(def))
        return value;
      value = def->getOperand(0);
    }
  }

  // Whether `value` is a view: it holds references but not one of its own.
  bool isView(Value value) {
    return counting.counted(value.getType()) && !isOwned(value.getType()) && !isStatic(value);
  }

  // Whether `value` may be used here: it holds a reference, or what it was
  // read from is alive, or it is a borrowed parameter.
  bool alive(Value value) {
    for (unsigned depth = 0; depth < 1024; ++depth) {
      if (!tracked(value) && !isView(value))
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
    if (!tracked(value))
      return success();
    int references = held.lookup(value);
    if (references < 1)
      return fail(op, value, "consumes a reference that the value does not hold here: it was "
                             "consumed before on this path");
    set(value, references - 1);
    return success();
  }

  LogicalResult use(Operation &op, Value value) {
    if (!alive(value))
      return fail(op, value, "uses a value whose last reference is gone on this path");
    return success();
  }

  // Every value `block` defines holds no reference at its end.
  LogicalResult settled(Block &block, Operation &at) {
    auto check = [&](Value value) -> LogicalResult {
      if (tracked(value) && held.lookup(value) != 0)
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

  Counting &counting;
  llvm::DenseMap<Value, int> held;
  llvm::DenseMap<Value, Value> owners;
  SmallVector<Change> log;
};

} // namespace idr::ownership
