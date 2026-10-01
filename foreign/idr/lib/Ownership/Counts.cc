// Explicit counting: the grades, idr.dup and idr.drop that make every
// reference consumed exactly once on every path (Perceus; Counting
// Immutable Beans' C). It runs on functional code, where a match region's
// yield is the join point and recursion is still a call.
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
//     value, so that the value it comes from can die before it (Beans:
//     `let y = proj x; inc y`). A field of a static value is static.
// A read of an owned value (a field, a match, a borrowed argument) reads a
// view of it (idr.borrow). Every drop of a region's entry comes after the
// dups of its fields, so the fields survive their scrutinee. Nothing is
// placed after a call whose arguments it consumes, so a self tail call
// stays one.

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
    ownFields();
    sinkConsumers();
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

  // An op without effects that consumes an owned value which later ops in
  // its block still read would cost that value one more reference: a dup
  // for the consumer, and a drop after the last read (a rebuilt wrapper
  // around an array that the inlined code goes on reading, where the
  // simplifier merged the rebuilds into the first). Moved down to its
  // result's first use, past those reads, the consumer takes the value
  // itself, and no count changes; moving later on the same path needs no
  // speculation. The ops that feed it and nothing else (the wrapper
  // entering its grade) move with it, and what they consume counts as its.
  void sinkConsumers() {
    fn.walk([&](Block *block) {
      // The consumers as the block holds them now, each considered once:
      // a moved one is not met again further down.
      SmallVector<Operation *> consumers;
      for (Operation &op : *block)
        if (op.getNumRegions() == 0 && op.getNumResults() != 0 &&
            llvm::any_of(op.getOpOperands(), [&](OpOperand &operand) {
              return counting.counted(operand.get().getType()) &&
                     useOf(operand, symbols) == Use::Consume &&
                     classOf(operand.get()) == Class::Owned;
            }))
          consumers.push_back(&op);
      for (Operation *op : consumers) {
        if (!movable(op))
          continue;
        Operation *target = nullptr;
        for (Value result : op->getResults())
          for (OpOperand &use : result.getUses())
            if (Operation *top = block->findAncestorOpInBlock(*use.getOwner());
                top && (!target || top->isBeforeInBlock(target)))
              target = top;
        if (!target || target == op->getNextNode())
          continue;
        SmallVector<Operation *> chain = feeders(op, *block);
        bool reads = false;
        for (Operation *link : chain)
          for (OpOperand &operand : link->getOpOperands()) {
            if (useOf(operand, symbols) != Use::Consume || classOf(operand.get()) != Class::Owned)
              continue;
            for (OpOperand &other : operand.get().getUses())
              if (Operation *top = block->findAncestorOpInBlock(*other.getOwner());
                  top && !llvm::is_contained(chain, top) && op->isBeforeInBlock(top) &&
                  top->isBeforeInBlock(target))
                reads = true;
          }
        if (!reads)
          continue;
        // The op first, then each feeder right before what it feeds.
        op->moveBefore(target);
        for (Operation *link : llvm::drop_begin(chain))
          link->moveBefore(link->getResults().front().getUses().begin()->getOwner());
      }
    });
  }

  // An op that may move later on its path: one without effects, or one
  // whose only effect is to be a linear value's one entry or use
  // (lin.enter, lin.use: an allocation on the linear resource, which no
  // memory holds).
  static bool movable(Operation *op) {
    if (isMemoryEffectFree(op))
      return true;
    auto iface = dyn_cast<MemoryEffectOpInterface>(op);
    if (!iface)
      return false;
    SmallVector<MemoryEffects::EffectInstance> effects;
    iface.getEffects(effects);
    return llvm::all_of(effects, [](const MemoryEffects::EffectInstance &effect) {
      return isa<MemoryEffects::Allocate>(effect.getEffect()) &&
             effect.getResource()->getResourceID() == LinResource::getResourceID();
    });
  }

  // `op`, then the movable ops of `block` that feed it and nothing else,
  // nearest first: a chain that moves as one.
  static SmallVector<Operation *> feeders(Operation *op, Block &block) {
    SmallVector<Operation *> chain{op};
    for (unsigned i = 0; i < chain.size(); ++i)
      for (Value operand : chain[i]->getOperands()) {
        Operation *def = operand.getDefiningOp();
        if (def && def->getBlock() == &block && def->getNumRegions() == 0 && movable(def) &&
            def->getNumResults() == 1 && def->getResult(0).hasOneUse() &&
            !llvm::is_contained(chain, def))
          chain.push_back(def);
      }
    return chain;
  }

  // A field that needs a reference of its own takes it where it is read:
  // an idr.dup of the field, which every use of the field then uses, and
  // which is placed as an owned value.
  void ownFields() {
    SmallVector<Value> fields;
    fn.walk<WalkOrder::PreOrder>([&](Block *block) {
      for (BlockArgument arg : block->getArguments())
        if (readFrom(arg) && classOf(arg) == Class::Owned)
          fields.push_back(arg);
      for (Operation &op : *block)
        for (Value result : op.getResults())
          if (readFrom(result) && classOf(result) == Class::Owned)
            fields.push_back(result);
    });
    for (Value field : fields) {
      if (field.use_empty())
        continue;
      OpBuilder b(fn.getContext());
      if (Operation *def = field.getDefiningOp())
        b.setInsertionPointAfter(def);
      else
        b.setInsertionPointToStart(cast<BlockArgument>(field).getOwner());
      auto dup = DupOp::create(b, field.getLoc(), owned(field.getType()), field);
      field.replaceAllUsesExcept(dup.getResult(), dup);
      classes.erase(field);
      ++incs;
    }
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
    takeReadSums();
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
      // The default region has the value itself back, not a view of it to
      // take a reference from while the value drops its own.
      Region *fallback = match.getDefaultRegion();
      if (fallback && !fallback->empty() && fallback->getNumArguments() == 1 &&
          !usedIn(value, *fallback) && !endsInCrash(fallback->front()))
        fallback->getArgument(0).replaceAllUsesWith(value);
    }
  }

  // An owned unboxed sum whose every use reads a field of one constructor
  // (a function's result of a record, a pair, an IORes) is its fields
  // already: they move out where it is defined, and the fields no one reads
  // are dropped there, instead of each field read taking a reference while
  // the sum drops all of its own.
  void takeReadSums() {
    SmallVector<Value> sums;
    auto consider = [&](Value value) {
      if (!isa<DataType>(unrestricted(value.getType())) || value.use_empty())
        return;
      auto first = dyn_cast<FieldOp>(*value.getUsers().begin());
      if (!first || !llvm::all_of(value.getUsers(), [&](Operation *user) {
            auto read = dyn_cast<FieldOp>(user);
            return read && read.getCtorAttr() == first.getCtorAttr();
          }))
        return;
      if (classOf(value) == Class::Owned)
        sums.push_back(value);
    };
    fn.walk([&](Operation *op) {
      for (Value result : op->getResults())
        consider(result);
    });
    // A sum read from another sum's field is taken apart first: taking
    // the outer one apart replaces, and erases, the read that defines it.
    for (Value value : llvm::reverse(sums)) {
      auto read = cast<FieldOp>(*value.getUsers().begin());
      auto ctor = SymbolRefAttr::get(getSumName(value.getType()).getAttr(), {read.getCtorAttr()});
      CtorOp decl = lookupCtor(read, ctor);
      if (!decl)
        continue;
      classes.erase(value);
      SmallVector<Type> fields;
      for (unsigned index = 0, e = static_cast<unsigned>(decl.getFieldTypes().size()); index < e;
           ++index)
        fields.push_back(fieldType(value.getType(), decl.getFieldType(index)));
      takeFields(value, ctor, fields);
    }
  }

  // A value that stands for one without holding a reference: poison, a
  // pending field, a small big. It is owned by type, and no count reaches
  // it.
  static bool phantom(Value value) {
    Operation *def = value.getDefiningOp();
    return isa_and_nonnull<ub::PoisonOp, PendingOp, BigSmallOp>(def);
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
  // where `op` uses what was read from it: an owned value is used again
  // after `op`, and a borrowed one is read from a value that is alive
  // there, or is a parameter. A match uses its scrutinee as it starts, so
  // a use of the value in one of its regions keeps it alive there too.
  bool aliveAt(Value value, Operation *op) {
    switch (classOf(value)) {
    case Class::Untracked:
    case Class::Static:
      return true;
    case Class::Owned:
      return usedAfter(value, op) ||
             (op->getNumRegions() != 0 && llvm::any_of(value.getUsers(), [&](Operation *user) {
                return op->isProperAncestor(user);
              }));
    case Class::Borrowed:
      break;
    }
    Value from = readFrom(value);
    return !from || aliveAt(from, op);
  }

  void plan(Value value, Block &block, Operation *def) {
    switch (classOf(value)) {
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
          if (operand.get() != value || useOf(operand, symbols) != Use::Consume)
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
        if (!isOwned(operand.get().getType()) || useOf(operand, symbols) != Use::Borrow)
          continue;
        b.setInsertionPoint(op);
        operand.set(BorrowOp::create(b, op->getLoc(), operand.get()).getResult());
      }
    });
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
