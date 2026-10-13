// The code counting changes before it places a count: what it cannot
// count, selects, values taken apart where they die, fields that take a
// reference of their own, and consumers moved past the reads that follow
// them.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/PatternMatch.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

using namespace mlir;

namespace idr::ownership {

namespace {

class Reshape {
public:
  Reshape(RewriterBase &rewriter, FuncOp fn, Counted &counted, Classes &classes,
          SymbolTable &symbols)
      : rewriter(rewriter), fn(fn), counted(counted), classes(classes), symbols(symbols) {}

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
      if (counted(select.getType()))
        selects.push_back(select);
    });
    for (arith::SelectOp select : selects) {
      rewriter.setInsertionPoint(select);
      Location loc = select.getLoc();
      auto match = MatchLitOp::create(
          rewriter, loc, TypeRange{select.getType()}, select.getCondition(),
          rewriter.getArrayAttr({rewriter.getIntegerAttr(select.getCondition().getType(), 1)}),
          2u);
      Value values[] = {select.getTrueValue(), select.getFalseValue()};
      for (auto [region, value] : llvm::zip(match.getRegions(), values)) {
        OpBuilder::InsertionGuard guard(rewriter);
        rewriter.createBlock(&region);
        YieldOp::create(rewriter, loc, value);
      }
      rewriter.replaceOp(select, match);
    }
  }

  // An owned scrutinee that dies in a case region is taken apart where it
  // dies: its fields move out of it instead of each taking one more
  // reference while it drops its own, which walks the cell's children to
  // drop theirs. Where the region begins when
  // nothing in it uses the box; else after its last use there, the
  // constructor known all along (whereDies, as reset/reuse places its
  // takes, only where a cell is reused; a box taken apart here is owned
  // already), when a field that holds references lives on past it
  // (keepsCountedField): one whose fields all die with it, or hold none, is
  // dropped as it was. A region that ends in a crash is left alone.
  void takeApart() {
    takeReadSums();
    takeReadBoxes();
    SmallVector<MatchOp> matches;
    fn.walk([&](MatchOp match) { matches.push_back(match); });
    for (MatchOp match : matches) {
      Value value = match.getScrutinee();
      if (classes.classOf(value) != Class::Owned || usedAfter(value, match))
        continue;
      DataOp data = lookupData(symbols, value.getType());
      for (auto [index, name] : llvm::enumerate(match.getCases().getAsRange<FlatSymbolRefAttr>())) {
        auto caseIndex = static_cast<unsigned>(index);
        Region &region = match.getCaseRegion(caseIndex);
        if (region.empty() || endsInCrash(region.front()))
          continue;
        if (!usedIn(value, region)) {
          takeAtEntry(rewriter, match, caseIndex, counted);
          continue;
        }
        CtorOp ctor = data ? lookupCtor(data, name.getValue()) : CtorOp();
        if (!ctor || !isa<BoxType>(unrestricted(value.getType())))
          continue;
        whereDies(value, region.front(), &symbols, [&](Block &block, Block::iterator at) {
          if (!endsInCrash(block) &&
              keepsCountedField(value, ctor, block, at, &region.front(), counted))
            takeAt(rewriter, value, ctor, block, at, &region.front(), counted);
        });
      }
      // The default region has the value itself back, not a view of it to
      // take a reference from while the value drops its own.
      Region *fallback = match.getDefaultRegion();
      if (fallback && !fallback->empty() && fallback->getNumArguments() == 1 &&
          !usedIn(value, *fallback) && !endsInCrash(fallback->front()))
        rewriter.replaceAllUsesWith(fallback->getArgument(0), value);
    }
  }

  // A field that needs a reference of its own takes it where it is read:
  // an idr.dup of the field, which every use of the field then uses, and
  // which is placed as an owned value.
  void ownFields() {
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
      rewriter.setInsertionPointAfterValue(field);
      auto dup = DupOp::create(rewriter, field.getLoc(), owned(field.getType()), field);
      rewriter.replaceAllUsesExcept(field, dup.getResult(), dup);
      classes.erase(field);
    }
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
    // The blocks are found first and sunk in after: a move changes the
    // block the walk is in.
    SmallVector<Block *> blocks;
    fn.walk([&](Block *block) { blocks.push_back(block); });
    for (Block *block : blocks) {
      // The consumers as the block holds them now, each considered once:
      // a moved one is not met again further down.
      SmallVector<Operation *> consumers;
      for (Operation &op : *block)
        if (op.getNumRegions() == 0 && op.getNumResults() != 0 &&
            llvm::any_of(op.getOpOperands(), [&](OpOperand &operand) {
              return counted(operand.get().getType()) && consumes(operand, &symbols) &&
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
            if (!consumes(operand, &symbols) || classes.classOf(operand.get()) != Class::Owned)
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
        rewriter.moveOpBefore(op, target);
        for (Operation *link : llvm::drop_begin(chain))
          rewriter.moveOpBefore(link, link->getResults().front().getUses().begin()->getOwner());
      }
    }
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
      CtorOp decl = lookupCtor(symbols, ctor);
      if (!decl)
        continue;
      classes.erase(value);
      SmallVector<Type> fields;
      for (unsigned index = 0, e = static_cast<unsigned>(decl.getFieldTypes().size()); index < e;
           ++index)
        fields.push_back(fieldType(value.getType(), decl.getFieldType(index)));
      takeFields(rewriter, value, ctor, fields, counted);
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
      CtorOp ctor = lookupCtor(symbols, name);
      if (!ctor)
        continue;
      whereDies(box, *first->getBlock(), &symbols, [&](Block &block, Block::iterator at) {
        if (!endsInCrash(block) && keepsCountedField(box, ctor, block, at, nullptr, counted))
          takeAt(rewriter, box, ctor, block, at, nullptr, counted);
      });
    }
  }

  // An op that may move later on its path: one without effects, or one
  // whose only effects are to be a linear value's one entry or use
  // (lin.enter, lin.use: an allocation on the linear resource, which no
  // memory holds) and to take over the owned values it consumes (a free of
  // their references, which go where it goes).
  static bool movable(Operation *op) {
    if (isMemoryEffectFree(op))
      return true;
    auto iface = dyn_cast<MemoryEffectOpInterface>(op);
    if (!iface)
      return false;
    SmallVector<MemoryEffects::EffectInstance> effects;
    iface.getEffects(effects);
    return llvm::all_of(effects, [](const MemoryEffects::EffectInstance &effect) {
      TypeID resource = effect.getResource()->getResourceID();
      return (isa<MemoryEffects::Allocate>(effect.getEffect()) &&
              resource == LinResource::getResourceID()) ||
             (isa<MemoryEffects::Free>(effect.getEffect()) &&
              resource == ReferenceResource::getResourceID());
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

  RewriterBase &rewriter;
  FuncOp fn;
  Counted &counted;
  Classes &classes;
  SymbolTable &symbols;
};

} // namespace

LogicalResult reshape(RewriterBase &rewriter, FuncOp fn, Counted &counted, Classes &classes,
                      SymbolTable &symbols, bool sink) {
  Reshape reshaping(rewriter, fn, counted, classes, symbols);
  if (failed(reshaping.check()))
    return failure();
  reshaping.rewriteSelects();
  reshaping.takeApart();
  reshaping.ownFields();
  if (sink)
    reshaping.sinkConsumers();
  return success();
}

} // namespace idr::ownership
