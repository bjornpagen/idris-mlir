// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Explicit counting: the grades, idr.dup and idr.drop that make every
// reference consumed exactly once on every path. It runs on functional
// code, where a match region's yield is the join point and recursion is
// still a call.
//
// Each value is placed on its own, along the ops of the block that
// defines it:
//   - an owned value (`!idr.own<T>`) holds one reference, which goes to its
//     last use on each path. A use that consumes a reference while the
//     value is still needed afterwards consumes an idr.dup of a view of it
//     instead; a last use that only reads is followed by an idr.drop; a
//     value nothing uses is dropped where it is defined. A match region
//     the value is not used in drops it on entry, unless it is still
//     needed after the match, and a region that ends in a crash is left
//     alone;
//   - a view (a borrowed parameter, a field, a constant) holds none: each
//     use that consumes one consumes an idr.dup of it;
//   - a field is a view when every use of it comes while the value it is
//     read from is still alive: a borrowed parameter, or an owned value
//     that is used again after it. Otherwise it takes a reference of its
//     own, an idr.dup where it is read, which is then placed as an owned
//     value, so that the value it comes from can die before it. A field
//     of a static value is static.
// A read of an owned value (a field, a match, a borrowed argument) reads a
// view of it (idr.borrow). Every drop of a region's entry comes after the
// dups of its fields, so the fields survive their scrutinee. Nothing is
// placed after a call whose arguments it consumes, so a self tail call
// stays one.
//
// Counting a function takes three steps: the classes of its values
// (Classes), the reshaping of its code before any count is placed
// (reshape), and the placement of the counts, here. A call's operand
// consumes what its callee's parameter grade says, read through the table:
// the operands take their callees' grades only once placed.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/MapVector.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;

namespace idr::ownership {

namespace {

struct Changes {
  SmallVector<Value> incs, decs;
};

class Placement {
public:
  Placement(RewriterBase &rewriter, FuncOp fn, Classes &classes, SymbolTable &symbols)
      : rewriter(rewriter), fn(fn), classes(classes), symbols(symbols) {}

  // Places every value of the function and materializes the counts.
  void run() {
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
    return consumes(operand, &symbols) || forced.contains(operand.getOwner());
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

  // The view of `value` at the insertion point: itself, or an idr.borrow
  // of an owned value.
  Value viewOf(Location loc, Value value) {
    return isOwned(value.getType()) ? BorrowOp::create(rewriter, loc, value).getResult() : value;
  }

  // At each point the dups come first: a dup never frees, and a field
  // takes its reference before the value it was read from drops its own.
  // Each planned reference goes to one consuming operand of the op, which
  // consumes an idr.dup of a view of the value in its place; the operand
  // left over, if any, consumes the value itself. Then every read of an
  // owned value reads a view of it.
  void materialize() {
    for (auto &[op, change] : changes) {
      rewriter.setInsertionPoint(op);
      Location loc = op->getLoc();
      llvm::MapVector<Value, unsigned> fresh;
      for (Value value : change.incs)
        ++fresh[value];
      for (auto [value, count] : fresh) {
        Value seen = viewOf(loc, value);
        for (OpOperand &operand : op->getOpOperands()) {
          if (count == 0)
            break;
          if (operand.get() != value || !takes(operand))
            continue;
          Value dup = DupOp::create(rewriter, loc, owned(seen.getType()), seen);
          rewriter.modifyOpInPlace(op, [&] { operand.set(dup); });
          --count;
        }
      }
      for (Value value : change.decs)
        DropOp::create(rewriter, loc, value);
    }
    // The reads are found first and given their views after: a view is
    // an op of its own, which the walk must not meet.
    SmallVector<OpOperand *> reads;
    fn.walk([&](Operation *op) {
      if (isa<BorrowOp>(op))
        return;
      for (OpOperand &operand : op->getOpOperands())
        if (isOwned(operand.get().getType()) && !takes(operand))
          reads.push_back(&operand);
    });
    for (OpOperand *operand : reads) {
      Operation *op = operand->getOwner();
      rewriter.setInsertionPoint(op);
      Value view = BorrowOp::create(rewriter, op->getLoc(), operand->get());
      rewriter.modifyOpInPlace(op, [&] { operand->set(view); });
    }
  }

  RewriterBase &rewriter;
  FuncOp fn;
  Classes &classes;
  SymbolTable &symbols;
  // The forces that take their cells over, where the cells die.
  llvm::SmallPtrSet<Operation *, 4> forced;
  // What goes right before each op.
  llvm::MapVector<Operation *, Changes> changes;
};

} // namespace

void place(RewriterBase &rewriter, FuncOp fn, Classes &classes, SymbolTable &symbols) {
  Placement(rewriter, fn, classes, symbols).run();
}

} // namespace idr::ownership
