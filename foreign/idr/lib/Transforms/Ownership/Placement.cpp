// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Explicit counting: the grades, idr.dup and idr.drop that make every
// reference consumed exactly once on every path. It runs on functional
// code, where a region's terminator is the join point and recursion is
// still a call.
//
// Each value is placed on its own, along the ops of the block that
// defines it:
//   - an owned value (`!idr.own<T>`) holds one reference, which goes to its
//     last use on each path. A use that consumes a reference while the
//     value is still needed afterwards consumes an idr.dup of a view of it
//     instead; a last use that only reads is followed by an idr.drop; a
//     value nothing uses is dropped where it is defined. An op that
//     decides (a match, an update of one element) moves it into each
//     region, and a region the value is not used in drops it on entry,
//     unless it is still needed after the op, or the op writes it; a
//     region that ends in a crash is left alone. Any other op
//     with regions (a loop) holds it for as long as it runs, each use
//     inside taking a view of it, and its last use is the op itself;
//   - a view (a borrowed parameter, a field, a constant, each at the view
//     grade `view(T)`, which is plain for a buffer's) holds none: each use
//     that consumes one consumes an idr.dup of it;
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
// Counting a function takes two steps: the reshaping of its code before
// any count is placed (reshape), and the placement of the counts, here.
// Each step reads the classes of the values (Classes) of the code as it
// stands when the step runs. A call's operand consumes what its callee's
// parameter grade says, read through the program's symbol table: the
// operands take their callees' grades only once placed.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/MapVector.h"

#include <cassert>

using namespace mlir;

namespace idr::ownership {

namespace {

struct Changes {
  SmallVector<Value> incs, decs;
};

class Placement {
public:
  Placement(RewriterBase &rewriter, FuncOp fn, const SymbolTable &symbols)
      : rewriter(rewriter), fn(fn), symbols(symbols) {}

  // Places every value of the function, grades the values it placed,
  // materializes the counts, and grades the views that are left; gives the
  // counts it added. Every class is decided, and every value placed, on
  // the function as it came: a graded buffer (`!idr.own<memref<...>>`) is
  // no operand an op of upstream's or an update over a buffer takes until
  // its read gets the plain view, so nothing is asked of such an op while
  // its operand is graded and its view not yet made.
  Counted run() {
    // The classes of the function as reshaping left it, the last change
    // they read.
    Classes classes(fn);
    SmallVector<std::pair<Value, Class>> values;
    fn.walk<WalkOrder::PreOrder>([&](Block *block) {
      for (BlockArgument arg : block->getArguments())
        values.emplace_back(arg, classes.classOf(arg));
      for (Operation &op : *block)
        for (Value result : op.getResults())
          values.emplace_back(result, classes.classOf(result));
    });
    for (auto [value, kind] : values)
      plan(value, kind);
    for (auto [value, type] : grades)
      value.setType(type);
    materialize();
    gradeViews();
    return counted;
  }

private:
  // Each value is placed from where it is defined, along the ops after it
  // in its block, as its class `kind` says.
  void plan(Value value, Class kind) {
    Point defined = definedAt(value);
    Block &block = blockOf(defined);
    Block::iterator from = firstAt(defined);
    switch (kind) {
    case Class::Untracked:
      return;
    case Class::Phantom:
      // Owned by type; no count reaches it.
      grades.emplace_back(value, owned(value.getType()));
      return;
    case Class::Constant:
      // A view, at the view grade, which each consuming use takes a
      // reference of its own to: no count reaches static data, so the dup
      // runs nothing.
      grades.emplace_back(value, view(value.getType()));
      placeBorrowed(value, block, from);
      return;
    case Class::StaticRead:
    case Class::Borrowed:
      // Graded as every read is.
      placeBorrowed(value, block, from);
      return;
    case Class::OwnedAtRead:
      // It took its reference where it was read (ownFields), in the dup
      // that every use of it now uses, which is placed as an owned value.
      return;
    case Class::Owned:
      grades.emplace_back(value, owned(value.getType()));
      placeOwned(value, block, from, /*keep=*/false);
      return;
    }
  }

  // How many operands of `op` are `value`, consuming and borrowing.
  std::pair<unsigned, unsigned> usesBy(Value value, Operation *op) {
    unsigned consumes = 0, borrows = 0;
    for (OpOperand &operand : op->getOpOperands())
      if (operand.get() == value)
        ++(takes(operand) ? consumes : borrows);
    return {consumes, borrows};
  }

  // Whether `operand` takes over the reference its value holds, as its op
  // declares.
  bool takes(OpOperand &operand) { return consumes(operand, &symbols); }

  // Whether `op` writes `value`, one of its own operands, and so holds it
  // until it is done: an update writes its element back into its array
  // once its region has run, so no region of it may drop the array, as a
  // region of a match drops what the match only read as it began.
  static bool writes(Operation *op, Value value) {
    auto effects = dyn_cast<MemoryEffectOpInterface>(op);
    if (!effects)
      return false;
    SmallVector<MemoryEffects::EffectInstance> instances;
    effects.getEffects(instances);
    return llvm::any_of(instances, [&](const MemoryEffects::EffectInstance &instance) {
      return isa<MemoryEffects::Write>(instance.getEffect()) && instance.getValue() == value;
    });
  }

  // The changes before the op at `from` in `block`. A field defined at
  // the point before it that takes a reference of its own does so right
  // there (ownFields), and the changes go after it: the field takes its
  // reference before the value it was read from drops its own. A block
  // ends in its terminator, which no such dup is, so an op is left.
  Changes &at(Block &block, Block::iterator from) {
    Point point = pointBefore(block, from);
    auto ownsField = [&](Operation &op) {
      auto dup = dyn_cast<DupOp>(op);
      return dup && definedAt(dup.getValue()) == point;
    };
    return changes[&*llvm::find_if_not(llvm::make_range(from, block.end()), ownsField)];
  }

  void incBeforeOp(Operation *op, Value value, unsigned times) {
    changes[op].incs.append(times, value);
  }

  // `value` holds one reference from the op at `from` on, which its last
  // use in `block` consumes, or which it still holds at the block's end
  // when `keep`.
  void placeOwned(Value value, Block &block, Block::iterator from, bool keep) {
    SmallVector<Operation *> users = usersIn(value, block, from);
    if (users.empty()) {
      if (!keep)
        at(block, from).decs.push_back(value);
      return;
    }
    for (auto [i, user] : llvm::enumerate(users)) {
      bool last = i + 1 == users.size() && !keep;
      if (decides(user) && !writes(user, value)) {
        // Each region takes the reference, or drops it on entry.
        for (Region &region : user->getRegions()) {
          if (region.empty())
            continue;
          Block &inner = region.front();
          if (usedIn(value, region))
            placeOwned(value, inner, inner.begin(), /*keep=*/!last);
          else if (last && !endsInCrash(inner))
            at(inner, inner.begin()).decs.push_back(value);
        }
        if (last)
          return;
        continue;
      }
      auto [consumes, borrows] = usesBy(value, user);
      // An op that does not decide may run its regions any number of
      // times: a value from outside it holds its reference throughout,
      // each use inside taking a view (or a dup, to consume), and the op
      // reads the value for as long as it runs.
      for (Region &region : user->getRegions())
        if (!region.empty() && usedIn(value, region)) {
          placeBorrowed(value, region.front(), region.front().begin());
          ++borrows;
        }
      if (!last) {
        incBeforeOp(user, value, consumes);
        continue;
      }
      if (borrows == 0 && consumes > 0) {
        incBeforeOp(user, value, consumes - 1);
        return;
      }
      incBeforeOp(user, value, consumes);
      // A terminator takes over what it passes on, as its flow says, so in
      // the owned stage no value's last use is a terminator that only reads
      // it: nothing follows a terminator to drop the value before. The
      // owned stage's verifier holds the rule.
      assert(!user->hasTrait<OpTrait::IsTerminator>() &&
             "the last use of an owned value is a terminator that does not take it over");
      at(block, std::next(user->getIterator())).decs.push_back(value);
      return;
    }
  }

  // `value` holds no reference; each use that consumes one gets its own. An
  // op that decides only reads what it decides on; any other op's operands
  // are placed as any op's, and the uses inside its regions as the uses in
  // the regions of one that decides.
  void placeBorrowed(Value value, Block &block, Block::iterator from) {
    for (Operation *user : usersIn(value, block, from)) {
      for (Region &region : user->getRegions())
        if (!region.empty() && usedIn(value, region))
          placeBorrowed(value, region.front(), region.front().begin());
      if (!decides(user))
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
          ++counted.dups;
        }
      }
      for (Value value : change.decs)
        DropOp::create(rewriter, loc, value);
      counted.drops += static_cast<unsigned>(change.decs.size());
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

  // Every read now reads a view, so what it reads is a view too: a field
  // read and a field a match binds are at their value's grade times the
  // field's (fieldType), which for a view is the view grade, and the
  // default region of a match, when it runs, takes back what the match
  // took. A walk in order reaches each read after the value it reads.
  void gradeViews() {
    fn.walk<WalkOrder::PreOrder>([&](Operation *op) {
      if (auto read = dyn_cast<FieldOp>(op)) {
        const Ctor &ctor = read.getDataType().getCtor(read.getTag());
        read.getResult().setType(
            fieldType(read.getValue().getType(), ctor.fields[static_cast<unsigned>(read.getIndex())]));
        return;
      }
      // A take's or an unpack's results are inferred from the value it takes
      // apart, which is graded now: each as inferred, an owned one kept at
      // the owned grade it has.
      if (isa<TakeOp, UnpackOp>(op)) {
        SmallVector<Type> types;
        if (failed(cast<InferTypeOpInterface>(op).inferReturnTypes(
                op->getContext(), op->getLoc(), op->getOperands(), op->getRawDictionaryAttrs(),
                op->getPropertiesStorage(), op->getRegions(), types)))
          return;
        for (auto [result, type] : llvm::zip_equal(op->getResults(), types))
          if (!(isOwned(result.getType()) && isOwned(type)))
            result.setType(type);
        return;
      }
      auto match = dyn_cast<MatchOpInterface>(op);
      if (!match)
        return;
      Type scrutinee = match.getScrutinee().getType();
      // A constructor's case binds its fields; a literal's binds nothing.
      if (auto cases = dyn_cast<MatchOp>(op)) {
        DataType data = cases.getDataType();
        for (unsigned index : llvm::seq(cases.getNumCases())) {
          const Ctor &ctor = data.getCtor(cases.getCaseTag(index));
          for (BlockArgument arg : cases.getCaseRegion(index).getArguments())
            arg.setType(fieldType(scrutinee, ctor.fields[arg.getArgNumber()]));
        }
      }
      // An exhaustive match's default region is empty: it never runs.
      if (Region &fallback = match.getDefaultRegion(); !fallback.empty())
        fallback.getArgument(0).setType(scrutinee);
    });
  }

  RewriterBase &rewriter;
  FuncOp fn;
  const SymbolTable &symbols;
  // The grade each placed value takes once every value is placed.
  SmallVector<std::pair<Value, Type>> grades;
  // What goes right before each op.
  llvm::MapVector<Operation *, Changes> changes;
  Counted counted;
};

} // namespace

Counted place(RewriterBase &rewriter, FuncOp fn, const SymbolTable &symbols) {
  return Placement(rewriter, fn, symbols).run();
}

} // namespace idr::ownership
