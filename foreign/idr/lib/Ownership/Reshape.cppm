// idr.ownership:reshape: the code counting changes before it places a count:
// what it cannot count, selects, values taken apart where they die, fields
// that take a reference of their own, and consumers moved past the reads
// that follow them. Nothing here is exported: insertCounts runs it.
export module idr.ownership:reshape;

import idr.mlir;
import idr.dialect;

import :arrayloop;
import :classes;
import :counting;
import :keepscountedfield;
import :onlyreads;
import :readfrom;
import :regions;
import :take;
import :takeatentry;
import :takefields;
import :usedafter;
import :useof;
import :wheredies;

using namespace mlir;

namespace idr::ownership {

class Reshape {
public:
  Reshape(func::FuncOp fn, Counting &counting, Classes &classes, SymbolTableCollection &symbols)
      : fn(fn), counting(counting), classes(classes), symbols(symbols) {}

  // The code this pass counts: blocks of one region each, with matches and
  // the loops over arrays as the only region ops.
  LogicalResult check() {
    WalkResult result = fn.walk([&](Operation *op) -> WalkResult {
      for (Region &region : op->getRegions())
        if (!region.empty() && !region.hasOneBlock())
          return op->emitOpError("idr-rc counts regions of one block only");
      if (op->getNumRegions() != 0 && op != fn.getOperation() &&
          !isa<MatchOp, MatchLitOp>(op) && !isArrayLoop(op))
        return op->emitOpError("idr-rc counts functional code, where matches and the loops "
                               "over arrays are the only ops with regions; it runs before "
                               "idr-tail-loops");
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

  // An owned scrutinee that dies in a case region is taken apart where it
  // dies (Perceus's drop specialization): its fields move out of it
  // instead of each taking one more reference while it drops its own, which
  // walks the cell's children to drop theirs. Where the region begins when
  // nothing in it uses the box; else after its last use there, the
  // constructor known all along (whereDies, as reset/reuse insertion
  // places its takes, which run before borrow inference and so only where
  // a cell is reused; a box taken apart here is owned already), when a
  // field that holds references lives on past it (keepsCountedField): one
  // whose fields all die with it, or hold none, is dropped as it was. A
  // region that ends in a crash is left alone.
  void takeApart() {
    takeReadSums();
    takeReadBoxes();
    SmallVector<MatchOp> matches;
    fn.walk([&](MatchOp match) { matches.push_back(match); });
    for (MatchOp match : matches) {
      Value value = match.getScrutinee();
      if (classes.classOf(value) != Class::Owned || usedAfter(value, match))
        continue;
      DataOp data = lookupData(match, value.getType());
      for (auto [index, name] : llvm::enumerate(match.getCases().getAsRange<FlatSymbolRefAttr>())) {
        auto caseIndex = static_cast<unsigned>(index);
        Region &region = match.getCaseRegion(caseIndex);
        if (region.empty() || endsInCrash(region.front()))
          continue;
        if (!usedIn(value, region)) {
          takeAtEntry(match, caseIndex);
          continue;
        }
        CtorOp ctor = data ? lookupCtor(data, name.getValue()) : CtorOp();
        if (!ctor || !isa<BoxType>(unrestricted(value.getType())))
          continue;
        whereDies(value, region.front(), symbols, [&](Block &block, Block::iterator at) {
          if (!endsInCrash(block) && keepsCountedField(value, ctor, block, at, &region.front()))
            takeAt(value, ctor, block, at, &region.front());
        });
      }
      // The default region has the value itself back, not a view of it to
      // take a reference from while the value drops its own.
      Region *fallback = match.getDefaultRegion();
      if (fallback && !fallback->empty() && fallback->getNumArguments() == 1 &&
          !usedIn(value, *fallback) && !endsInCrash(fallback->front()))
        fallback->getArgument(0).replaceAllUsesWith(value);
    }
  }

  // A field that needs a reference of its own takes it where it is read:
  // an idr.dup of the field, which every use of the field then uses, and
  // which is placed as an owned value. Returns how many it added.
  unsigned ownFields() {
    unsigned incs = 0;
    SmallVector<Value> fields;
    fn.walk<WalkOrder::PreOrder>([&](Block *block) {
      for (BlockArgument arg : block->getArguments())
        if (readFrom(arg) && classes.classOf(arg) == Class::Owned)
          fields.push_back(arg);
      for (Operation &op : *block)
        for (Value result : op.getResults())
          if (readFrom(result) && classes.classOf(result) == Class::Owned)
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
    return incs;
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
                     classes.classOf(operand.get()) == Class::Owned;
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
            if (useOf(operand, symbols) != Use::Consume ||
                classes.classOf(operand.get()) != Class::Owned)
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

private:
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
      if (classes.classOf(value) == Class::Owned)
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

  // An owned box that no match takes apart, whose every use reads a field
  // of one constructor (a nested pattern reads the fields of a box an outer
  // one matched): its constructor is known from its first read on, and it
  // dies after its last, where it is taken apart as a matched box is when a
  // field that holds references lives on past it.
  void takeReadBoxes() {
    SmallVector<std::pair<Value, FieldOp>> boxes;
    auto consider = [&](Value box) {
      if (FieldOp first = onlyReads(box); first && classes.classOf(box) == Class::Owned)
        boxes.emplace_back(box, first);
    };
    fn.walk<WalkOrder::PreOrder>([&](Block *block) {
      for (BlockArgument arg : block->getArguments())
        consider(arg);
      for (Operation &op : *block)
        for (Value result : op.getResults())
          consider(result);
    });
    for (auto [box, first] : boxes) {
      auto name = SymbolRefAttr::get(getSumName(box.getType()).getAttr(), {first.getCtorAttr()});
      CtorOp ctor = lookupCtor(first, name);
      if (!ctor)
        continue;
      whereDies(box, *first->getBlock(), symbols, [&](Block &block, Block::iterator at) {
        if (!endsInCrash(block) && keepsCountedField(box, ctor, block, at, nullptr))
          takeAt(box, ctor, block, at, nullptr);
      });
    }
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

  func::FuncOp fn;
  Counting &counting;
  Classes &classes;
  SymbolTableCollection &symbols;
};

} // namespace idr::ownership
