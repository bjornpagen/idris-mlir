// idr.ownership:placement: the counts of a function: where each value's
// references go, and the idr.dup, idr.drop and idr.borrow that make them
// so. Nothing here is exported: insertCounts runs it.
export module idr.ownership:placement;

import idr.mlir;
import idr.dialect;

import :arrayloop;
import :classes;
import :readfrom;
import :regions;
import :usersin;

using namespace mlir;

namespace idr::ownership {

struct Changes {
  SmallVector<Value> incs, decs;
};

class Placement {
public:
  Placement(func::FuncOp fn, Classes &classes) : fn(fn), classes(classes) {}

  // Places every value of the function and materializes the counts.
  // Returns the numbers of incs and decs added.
  std::pair<unsigned, unsigned> run() {
    SmallVector<std::tuple<Value, Block *, Operation *>> values;
    fn.walk<WalkOrder::PreOrder>([&](Block *block) {
      for (BlockArgument arg : block->getArguments())
        values.emplace_back(arg, block, nullptr);
      for (Operation &op : *block)
        for (Value result : op.getResults())
          values.emplace_back(result, block, &op);
    });
    for (auto [value, block, def] : values)
      plan(value, *block, def);
    materialize();
    return std::make_pair(incs, decs);
  }

private:
  // A value that stands for one without holding a reference: poison, a
  // pending field, a small big. It is owned by type, and no count reaches
  // it.
  static bool phantom(Value value) {
    Operation *def = value.getDefiningOp();
    return isa_and_nonnull<ub::PoisonOp, PendingOp, BigSmallOp>(def);
  }

  void plan(Value value, Block &block, Operation *def) {
    switch (classes.classOf(value)) {
    case Class::Untracked:
      return;
    case Class::Static:
      // A value that stands for one is owned by type; a constant is a
      // view, which each consuming use takes a reference of its own to (no
      // count reaches static data, so the dup runs nothing).
      if (phantom(value))
        value.setType(owned(value.getType()));
      else
        placeBorrowed(value, block, def);
      return;
    case Class::Borrowed:
      placeBorrowed(value, block, def);
      return;
    case Class::Owned:
      break;
    }
    // A field that needs its own reference took it in ownFields; what is
    // left reading from a value is a view.
    if (readFrom(value))
      return;
    value.setType(owned(value.getType()));
    placeOwned(value, block, def, /*keep=*/false);
  }

  // How many operands of `op` are `value`, consuming and borrowing.
  std::pair<unsigned, unsigned> usesBy(Value value, Operation *op) {
    unsigned consumes = 0, borrows = 0;
    for (OpOperand &operand : op->getOpOperands())
      if (operand.get() == value)
        ++(takes(operand) ? consumes : borrows);
    return {consumes, borrows};
  }

  // Whether `operand` takes over the reference its value holds: where its
  // op declares so, and at a force this placement gives its cell owned.
  bool takes(OpOperand &operand) {
    return consumes(operand) || forced.contains(operand.getOwner());
  }

  // The changes right after `def` in `block`, or at its start when null.
  // Nothing follows a terminator, so that point is before an op too. A
  // field that takes a reference of its own does so right there
  // (ownFields), and the point is after it: the field takes its reference
  // before the value it was read from drops its own.
  Changes &at(Block &block, Operation *def) {
    Operation *point = def ? def->getNextNode() : &block.front();
    auto ownsField = [&](Operation *op) {
      auto dup = dyn_cast<DupOp>(op);
      if (!dup)
        return false;
      Value field = dup.getValue();
      return def ? field.getDefiningOp() == def
                 : isa<BlockArgument>(field) && cast<BlockArgument>(field).getOwner() == &block;
    };
    while (point && ownsField(point))
      point = point->getNextNode();
    return changes[point];
  }

  void incBeforeOp(Operation *op, Value value, unsigned times) {
    for (unsigned i = 0; i < times; ++i)
      changes[op].incs.push_back(value);
  }

  // `value` holds one reference from `after` on (from the block's start
  // when null), which its last use in `block` consumes, or which it still
  // holds at the block's end when `keep`.
  void placeOwned(Value value, Block &block, Operation *after, bool keep) {
    SmallVector<Operation *> users = usersIn(value, block, after);
    if (users.empty()) {
      if (!keep)
        at(block, after).decs.push_back(value);
      return;
    }
    for (auto [i, user] : llvm::enumerate(users)) {
      bool last = i + 1 == users.size() && !keep;
      if (user->getNumRegions() != 0 && !isArrayLoop(user)) {
        // Each region takes the reference, or drops it on entry.
        for (Region &region : user->getRegions()) {
          if (region.empty())
            continue;
          Block &inner = region.front();
          if (usedIn(value, region))
            placeOwned(value, inner, nullptr, /*keep=*/!last);
          else if (last && !endsInCrash(inner))
            at(inner, nullptr).decs.push_back(value);
        }
        if (last)
          return;
        continue;
      }
      auto [consumes, borrows] = usesBy(value, user);
      // The body of a loop runs once per index it covers: a value from
      // outside it holds its reference throughout, each use inside taking a
      // view (or a dup, to consume), and the loop reads the value for as
      // long as it runs.
      if (isArrayLoop(user))
        for (Region &region : user->getRegions())
          if (!region.empty() && usedIn(value, region)) {
            placeBorrowed(value, region.front(), nullptr);
            ++borrows;
          }
      if (!last) {
        incBeforeOp(user, value, consumes);
        continue;
      }
      // A force reads its cell, except where the cell dies: there it takes
      // the cell over, owned, so that a cell nothing else holds is forced
      // once and freed instead of keeping a memo no one will read.
      if (isa<ForceOp>(user)) {
        forced.insert(user);
        return;
      }
      if (borrows == 0 && consumes > 0) {
        incBeforeOp(user, value, consumes - 1);
      } else {
        incBeforeOp(user, value, consumes);
        at(block, user).decs.push_back(value);
      }
      return;
    }
  }

  // `value` holds no reference; each use that consumes one gets its own. A
  // match only reads its scrutinee; a loop's operands are placed as any
  // op's, and the uses inside its body as the uses in a match's regions.
  void placeBorrowed(Value value, Block &block, Operation *after) {
    for (Operation *user : usersIn(value, block, after)) {
      for (Region &region : user->getRegions())
        if (!region.empty() && usedIn(value, region))
          placeBorrowed(value, region.front(), nullptr);
      if (user->getNumRegions() == 0 || isArrayLoop(user))
        incBeforeOp(user, value, usesBy(value, user).first);
    }
  }

  // The view of `value` at `b`: itself, or an idr.borrow of an owned value.
  static Value viewOf(OpBuilder &b, Location loc, Value value) {
    return isOwned(value.getType()) ? BorrowOp::create(b, loc, value).getResult() : value;
  }

  // At each point the dups come first: a dup never frees, and a field
  // takes its reference before the value it was read from drops its own.
  // Each planned reference goes to one consuming operand of the op, which
  // consumes an idr.dup of a view of the value in its place; the operand
  // left over, if any, consumes the value itself. Then every read of an
  // owned value reads a view of it.
  void materialize() {
    OpBuilder b(fn.getContext());
    for (auto &[op, change] : changes) {
      b.setInsertionPoint(op);
      Location loc = op->getLoc();
      llvm::MapVector<Value, unsigned> fresh;
      for (Value value : change.incs)
        ++fresh[value];
      for (auto [value, count] : fresh) {
        Value seen = viewOf(b, loc, value);
        for (OpOperand &operand : op->getOpOperands()) {
          if (count == 0)
            break;
          if (operand.get() != value || !takes(operand))
            continue;
          operand.set(DupOp::create(b, loc, owned(seen.getType()), seen).getResult());
          --count;
        }
      }
      for (Value value : change.decs)
        DropOp::create(b, loc, value);
      incs += static_cast<unsigned>(change.incs.size());
      decs += static_cast<unsigned>(change.decs.size());
    }
    fn.walk([&](Operation *op) {
      if (isa<BorrowOp>(op))
        return;
      for (OpOperand &operand : op->getOpOperands()) {
        if (!isOwned(operand.get().getType()) || takes(operand))
          continue;
        b.setInsertionPoint(op);
        operand.set(BorrowOp::create(b, op->getLoc(), operand.get()).getResult());
      }
    });
  }

  func::FuncOp fn;
  Classes &classes;
  // The forces that take their cells over, where the cells die.
  llvm::SmallPtrSet<Operation *, 4> forced;
  // What goes right before each op.
  llvm::MapVector<Operation *, Changes> changes;
  unsigned incs = 0, decs = 0;
};

} // namespace idr::ownership
