// Explicit counting: the idr.inc and idr.dec that make every reference
// consumed exactly once on every path (Perceus; Counting Immutable Beans'
// C). It runs on functional code, where a match region's yield is the join
// point and recursion is still a call.
//
// Each value is placed on its own, along the ops of the block that
// defines it:
//   - an owned value's reference goes to its last use on each path. A use
//     that consumes a reference while the value is still needed afterwards
//     gets an idr.inc first; a last use that only borrows is followed by an
//     idr.dec; a value nothing uses is dropped where it is defined. A match
//     region the value is not used in drops it on entry, unless it is still
//     needed after the match, and a region that ends in a crash is left
//     alone;
//   - a borrowed value gets an idr.inc before each use that consumes;
//   - a field is borrowed when every use of it comes while the value it is
//     read from is still alive: a borrowed parameter, or an owned value
//     that is used again after it. Otherwise it takes a reference of its
//     own, with an idr.inc where it is read, so that the value it comes
//     from can die before it (Beans: `let y = proj x; inc y`). A field of a
//     static value is static.
// Every drop of a region's entry comes after the idr.inc of its fields, so
// the fields survive their scrutinee. Nothing is placed after a call whose
// arguments it consumes, so a self tail call stays one.

#include "Ownership/Ownership.h"

#include "llvm/ADT/MapVector.h"

using namespace mlir;

namespace idr::ownership {

namespace {

enum class Class { Untracked, Static, Borrowed, Owned };

struct Changes {
  SmallVector<Value> incs, decs;
};

class Counter {
public:
  Counter(func::FuncOp fn, Counting &counting) : fn(fn), counting(counting) {}

  FailureOr<std::pair<unsigned, unsigned>> run() {
    if (failed(check()))
      return failure();
    rewriteSelects();
    takeApart();
    fn.walk<WalkOrder::PreOrder>([&](Block *block) {
      for (BlockArgument arg : block->getArguments())
        plan(arg, *block, nullptr);
      for (Operation &op : *block)
        for (Value result : op.getResults())
          plan(result, *block, &op);
    });
    materialize();
    return std::make_pair(incs, decs);
  }

private:
  // The code this pass counts: blocks of one region each, with matches as
  // the only region ops.
  LogicalResult check() {
    WalkResult result = fn.walk([&](Operation *op) -> WalkResult {
      for (Region &region : op->getRegions())
        if (!region.empty() && !region.hasOneBlock())
          return op->emitOpError("idr-rc counts regions of one block only");
      if (op->getNumRegions() != 0 && op != fn.getOperation() &&
          !isa<MatchOp, MatchLitOp>(op))
        return op->emitOpError("idr-rc counts functional code, where matches are the only "
                               "ops with regions; it runs before idr-tail-loops");
      return WalkResult::advance();
    });
    return failure(result.wasInterrupted());
  }

  // A select of values that hold references becomes a match, whose regions
  // consume what they yield.
  void rewriteSelects() {
    SmallVector<arith::SelectOp> selects;
    fn.walk([&](arith::SelectOp select) {
      if (counting.counted(select.getType()))
        selects.push_back(select);
    });
    for (arith::SelectOp select : selects) {
      OpBuilder b(select);
      Location loc = select.getLoc();
      auto match = MatchLitOp::create(
          b, loc, TypeRange{select.getType()}, select.getCondition(),
          b.getArrayAttr({b.getIntegerAttr(select.getCondition().getType(), 1)}), 2u);
      for (auto [region, value] :
           llvm::zip(match.getRegions(), ValueRange{select.getTrueValue(), select.getFalseValue()})) {
        OpBuilder::InsertionGuard guard(b);
        b.createBlock(&region);
        YieldOp::create(b, loc, value);
      }
      select.getResult().replaceAllUsesWith(match.getResult(0));
      select.erase();
    }
  }

  // An owned scrutinee that dies where a case region begins is taken
  // apart there: its fields move out of it instead of each taking one more
  // reference while it drops its own.
  void takeApart() {
    SmallVector<MatchOp> matches;
    fn.walk([&](MatchOp match) { matches.push_back(match); });
    for (MatchOp match : matches) {
      Value value = match.getScrutinee();
      if (classOf(value) != Class::Owned || usedAfter(value, match))
        continue;
      for (unsigned index = 0, e = static_cast<unsigned>(match.getCases().size()); index < e;
           ++index) {
        Region &region = match.getCaseRegion(index);
        if (!region.empty() && !usedIn(value, region) && !endsInCrash(region.front()))
          takeAtEntry(match, index);
      }
    }
  }

  Class classOf(Value value) {
    if (!counting.counted(value.getType()))
      return Class::Untracked;
    if (isStatic(value))
      return Class::Static;
    auto known = classes.find(value);
    if (known != classes.end())
      return known->second;
    Class result = Class::Owned;
    if (Value from = readFrom(value)) {
      if (llvm::all_of(value.getUsers(), [&](Operation *user) { return aliveAt(from, user); }))
        result = Class::Borrowed;
    } else if (auto arg = dyn_cast<BlockArgument>(value);
               arg && arg.getOwner()->getParentOp() == fn.getOperation()) {
      if (isBorrowed(fn, arg.getArgNumber()))
        result = Class::Borrowed;
    }
    classes[value] = result;
    return result;
  }

  // Whether `value` still holds a reference, or lives as long as the call,
  // for all of `op`: an owned value is used again after it, and a borrowed
  // one is read from a value that is alive there, or is a parameter.
  bool aliveAt(Value value, Operation *op) {
    switch (classOf(value)) {
    case Class::Untracked:
    case Class::Static:
      return true;
    case Class::Owned:
      return usedAfter(value, op);
    case Class::Borrowed:
      break;
    }
    Value from = readFrom(value);
    return !from || aliveAt(from, op);
  }

  void plan(Value value, Block &block, Operation *def) {
    switch (classOf(value)) {
    case Class::Untracked:
    case Class::Static:
      return;
    case Class::Borrowed:
      placeBorrowed(value, block, def);
      return;
    case Class::Owned:
      break;
    }
    if (readFrom(value)) {
      // A field takes its own reference where it is read.
      if (value.use_empty())
        return;
      at(block, def).incs.push_back(value);
    }
    placeOwned(value, block, def, /*keep=*/false);
  }

  // The ops of `block` after `after` (from its start when null) that use
  // `value`, themselves or in their regions, in order.
  SmallVector<Operation *> usersIn(Value value, Block &block, Operation *after) {
    SmallVector<Operation *> users;
    for (OpOperand &use : value.getUses()) {
      Operation *top = block.findAncestorOpInBlock(*use.getOwner());
      if (top && (!after || after->isBeforeInBlock(top)))
        users.push_back(top);
    }
    llvm::sort(users, [](Operation *a, Operation *b) { return a->isBeforeInBlock(b); });
    users.erase(std::unique(users.begin(), users.end()), users.end());
    return users;
  }

  static bool usedIn(Value value, Region &region) {
    return llvm::any_of(value.getUses(), [&](OpOperand &use) {
      return region.isAncestor(use.getOwner()->getParentRegion());
    });
  }

  static bool endsInCrash(Block &block) {
    return !block.empty() && isa<ub::UnreachableOp>(block.back());
  }

  // How many operands of `op` are `value`, consuming and borrowing.
  std::pair<unsigned, unsigned> usesBy(Value value, Operation *op) {
    unsigned consumes = 0, borrows = 0;
    for (OpOperand &operand : op->getOpOperands())
      if (operand.get() == value)
        ++(useOf(operand, symbols) == Use::Consume ? consumes : borrows);
    return {consumes, borrows};
  }

  // The changes right after `def` in `block`, or at its start when null.
  // Nothing follows a terminator, so that point is before an op too.
  Changes &at(Block &block, Operation *def) {
    return changes[def ? def->getNextNode() : &block.front()];
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
      if (user->getNumRegions() != 0) {
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
      if (!last) {
        incBeforeOp(user, value, consumes);
        continue;
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

  // `value` holds no reference; each use that consumes one gets its own.
  void placeBorrowed(Value value, Block &block, Operation *after) {
    for (Operation *user : usersIn(value, block, after)) {
      if (user->getNumRegions() == 0) {
        incBeforeOp(user, value, usesBy(value, user).first);
        continue;
      }
      for (Region &region : user->getRegions())
        if (!region.empty() && usedIn(value, region))
          placeBorrowed(value, region.front(), nullptr);
    }
  }

  // At each point the incs come first: an inc never frees, and a field
  // takes its reference before the value it was read from drops its own.
  void materialize() {
    OpBuilder b(fn.getContext());
    for (auto &[op, change] : changes) {
      b.setInsertionPoint(op);
      for (Value value : change.incs)
        IncOp::create(b, op->getLoc(), value);
      for (Value value : change.decs)
        DecOp::create(b, op->getLoc(), value);
      incs += static_cast<unsigned>(change.incs.size());
      decs += static_cast<unsigned>(change.decs.size());
    }
  }

  func::FuncOp fn;
  Counting &counting;
  SymbolTableCollection symbols;
  llvm::DenseMap<Value, Class> classes;
  // What goes right before each op.
  llvm::MapVector<Operation *, Changes> changes;
  unsigned incs = 0, decs = 0;
};

} // namespace

FailureOr<std::pair<unsigned, unsigned>> insertCounts(func::FuncOp fn, Counting &counting) {
  return Counter(fn, counting).run();
}

} // namespace idr::ownership
