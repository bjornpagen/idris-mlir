// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The code counting changes in one function before it places a count:
// selects, values taken apart where they die, fields and elements that
// take a reference of their own, and consumers moved past the reads that
// follow them.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Support/Worklist.h"
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
  Reshape(RewriterBase &rewriter, FuncOp fn, const SymbolTable &symbols)
      : rewriter(rewriter), fn(fn), symbols(symbols) {}

  // A select of values that hold references becomes a match, whose regions
  // consume what they yield: the true value in the case of 1, the false
  // one in the default, which binds the condition back.
  void rewriteSelects() {
    SmallVector<arith::SelectOp> selects;
    fn.walk([&](arith::SelectOp select) {
      if (holdsReferences(select.getType()))
        selects.push_back(select);
    });
    for (arith::SelectOp select : selects) {
      rewriter.setInsertionPoint(select);
      Location loc = select.getLoc();
      Value condition = select.getCondition();
      auto match = MatchLitOp::create(
          rewriter, loc, TypeRange{select.getType()}, condition,
          rewriter.getArrayAttr({rewriter.getIntegerAttr(condition.getType(), 1)}));
      {
        OpBuilder::InsertionGuard guard(rewriter);
        rewriter.createBlock(&match.getCaseRegion(0));
        YieldOp::create(rewriter, loc, select.getTrueValue());
        rewriter.createBlock(&match.getDefaultRegion(), {}, {condition.getType()}, {loc});
        YieldOp::create(rewriter, loc, select.getFalseValue());
      }
      rewriter.replaceOp(select, match);
    }
  }

  // An owned scrutinee that dies in a case region, and is no memo cell,
  // whose constructor a force may change under the match, is taken apart
  // where it dies: its fields move out of it instead of each taking one more
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
      // Each match is decided on the function as the takes before it left
      // it, so its classes are built for it.
      Value value = match.getScrutinee();
      if (!ownsReference(Classes(fn).classOf(value)) || isMemoCell(value.getType()) ||
          usedAfter(value, match))
        continue;
      for (unsigned caseIndex : llvm::seq(match.getNumCases())) {
        Region &region = match.getCaseRegion(caseIndex);
        if (endsInCrash(region.front()))
          continue;
        if (!usedIn(value, region)) {
          takeAtEntry(rewriter, match, caseIndex);
          continue;
        }
        // Only a cell's fields move out where the value dies in the
        // region: an unboxed sum is its fields already.
        Tag tag = match.getCaseTag(caseIndex);
        if (!buildsCell(value.getType(), tag))
          continue;
        ArrayRef<BlockArgument> bound = region.front().getArguments();
        whereDies(value, region.front(), [&](OpOperand &use) { return takesOver(use); },
                  [&](Block &block, Block::iterator at) {
          if (!endsInCrash(block) && keepsCountedField(value, tag, block, at, bound))
            takeAt(rewriter, value, tag, block, at, bound);
        });
      }
      // The default region, when it runs, has the value itself back, not a
      // view of it to take a reference from while the value drops its own.
      Region &fallback = match.getDefaultRegion();
      if (!fallback.empty() && !usedIn(value, fallback) && !endsInCrash(fallback.front()))
        rewriter.replaceAllUsesWith(fallback.getArgument(0), value);
    }
  }

  // A field that needs a reference of its own takes it where it is read:
  // an idr.dup of the field, which every use of the field then uses, and
  // which is placed as an owned value. So does every element read from a
  // buffer, right after its load. Gives the dups it made.
  unsigned ownFields() {
    // On the function as the sinking left it: the classes the counts are
    // placed by agree with these, since a dup only gives its field a use
    // that reads it.
    Classes classes(fn);
    SmallVector<Value> fields;
    fn.walk<WalkOrder::PreOrder>([&](Block *block) {
      for (BlockArgument arg : block->getArguments())
        if (classes.classOf(arg) == Class::OwnedAtRead)
          fields.push_back(arg);
      for (Operation &op : *block)
        for (Value result : op.getResults())
          if (classes.classOf(result) == Class::OwnedAtRead)
            fields.push_back(result);
    });
    unsigned dups = 0;
    for (Value field : fields) {
      if (field.use_empty())
        continue;
      rewriter.setInsertionPointAfterValue(field);
      auto dup = DupOp::create(rewriter, field.getLoc(), owned(field.getType()), field);
      rewriter.replaceAllUsesExcept(field, dup.getResult(), dup);
      ++dups;
    }
    return dups;
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
      // a moved one is not met again further down. The block's classes are
      // built before its moves and only choose what moves: a move of an op
      // without effects is always one the counts can be placed on, and the
      // classes the counts are placed by are built after every move.
      Classes classes(fn);
      SmallVector<Operation *> consumers;
      for (Operation &op : *block)
        if (op.getNumRegions() == 0 && op.getNumResults() != 0 &&
            llvm::any_of(op.getOpOperands(), [&](OpOperand &operand) {
              return holdsReferences(operand.get().getType()) && takesOver(operand) &&
                     ownsReference(classes.classOf(operand.get()));
            }))
          consumers.push_back(&op);
      for (Operation *op : consumers) {
        if (!movable(op))
          continue;
        // The first op of the block that uses a result: where the op goes.
        SmallVector<Operation *> users = usersIn(op->getResults(), *block);
        if (users.empty() || users.front() == op->getNextNode())
          continue;
        Operation *target = users.front();
        SmallVector<Operation *> chain = feeders(op, *block);
        // Whether an op of the block between `op` and `target`, outside
        // the chain, reads `value`.
        auto readBetween = [&](Value value) {
          return llvm::any_of(value.getUses(), [&](OpOperand &other) {
            Operation *top = block->findAncestorOpInBlock(*other.getOwner());
            return top && !llvm::is_contained(chain, top) && op->isBeforeInBlock(top) &&
                   top->isBeforeInBlock(target);
          });
        };
        // What the chain consumes owned, and the fields read from it: the
        // inlined code around an array goes on reading and writing the
        // array's memref field while the array itself is what enters its
        // grade for the next call.
        auto readOn = [&](OpOperand &operand) {
          if (!takesOver(operand) || !ownsReference(classes.classOf(operand.get())))
            return false;
          Value value = operand.get();
          return readBetween(value) || llvm::any_of(value.getUsers(), [&](Operation *user) {
                   return isa<FieldOp>(user) && user->getNumResults() == 1 &&
                          readBetween(user->getResult(0));
                 });
        };
        if (llvm::none_of(chain, [&](Operation *link) {
              return llvm::any_of(link->getOpOperands(), readOn);
            }))
          continue;
        // The op first, then each feeder right before what it feeds.
        rewriter.moveOpBefore(op, target);
        for (Operation *link : llvm::drop_begin(chain))
          rewriter.moveOpBefore(link, link->getResults().front().getUses().begin()->getOwner());
      }
    }
  }

private:
  // Whether `use` takes over its value's reference, a call's argument as
  // its callee's signature grades it.
  bool takesOver(OpOperand &use) const { return consumes(use, &symbols); }

  // The ops of `block` that use any of `values`, themselves or in their
  // regions, in order, once each.
  static SmallVector<Operation *> usersIn(ValueRange values, Block &block) {
    SmallVector<OpOperand *> uses;
    for (Value value : values)
      llvm::append_range(uses, llvm::make_pointer_range(value.getUses()));
    return ownership::usersIn(uses, block, block.begin());
  }

  // An owned unboxed sum whose every use reads a field of one constructor
  // (a function's result of a record, a pair, an IORes) is its fields
  // already: they move out where it is defined, and the fields no one reads
  // are dropped there, instead of each field read taking a reference while
  // the sum drops all of its own.
  void takeReadSums() {
    Classes classes(fn);
    SmallVector<Value> sums;
    auto consider = [&](Value value) {
      if (!isa<DataType>(unrestricted(value.getType())) || value.use_empty())
        return;
      auto first = dyn_cast<FieldOp>(*value.getUsers().begin());
      if (!first || !llvm::all_of(value.getUsers(), [&](Operation *user) {
            auto read = dyn_cast<FieldOp>(user);
            return read && read.getTag() == first.getTag();
          }))
        return;
      if (ownsReference(classes.classOf(value)))
        sums.push_back(value);
    };
    fn.walk([&](Operation *op) {
      for (Value result : op->getResults())
        consider(result);
    });
    // A sum read from another sum's field is taken apart first: taking
    // the outer one apart replaces, and erases, the read that defines it.
    for (Value value : llvm::reverse(sums))
      takeFields(rewriter, value, cast<FieldOp>(*value.getUsers().begin()).getTag());
  }

  // An owned box that no match takes apart, whose every use reads a field
  // of one constructor (a nested pattern reads the fields of a box an outer
  // one matched): its constructor is known from its first read on, and it
  // dies after its last, where it is taken apart as a matched box is when a
  // field that holds references lives on past it.
  void takeReadBoxes() {
    Classes classes(fn);
    SmallVector<std::pair<Value, FieldOp>> boxes;
    auto consider = [&](Value box) {
      if (FieldOp first = onlyReads(box);
          first && !isMemoCell(box.getType()) && ownsReference(classes.classOf(box)))
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
      Tag tag = first.getTag();
      whereDies(box, *first->getBlock(), [&](OpOperand &use) { return takesOver(use); },
                [&](Block &block, Block::iterator at) {
        if (!endsInCrash(block) && keepsCountedField(box, tag, block, at, {}))
          takeAt(rewriter, box, tag, block, at, {});
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
  // nearest first: a chain that moves as one, each op in it once.
  static SmallVector<Operation *> feeders(Operation *op, Block &block) {
    OnceWorklist<Operation *> chain;
    (void)chain.push(op);
    while (std::optional<Operation *> link = chain.pop())
      for (Value operand : (*link)->getOperands()) {
        Operation *def = operand.getDefiningOp();
        if (def && def->getBlock() == &block && def->getNumRegions() == 0 && movable(def) &&
            def->getNumResults() == 1 && def->getResult(0).hasOneUse())
          (void)chain.push(def);
      }
    return SmallVector<Operation *>(chain.entered());
  }

  RewriterBase &rewriter;
  FuncOp fn;
  const SymbolTable &symbols;
};

} // namespace

Counted reshape(RewriterBase &rewriter, FuncOp fn, const SymbolTable &symbols) {
  Reshape reshaping(rewriter, fn, symbols);
  reshaping.rewriteSelects();
  reshaping.takeApart();
  // Consumers move past the reads that follow them before a field takes
  // a reference of its own: moved, the consumer is what keeps the field's
  // root alive at those reads, so the field needs none.
  reshaping.sinkConsumers();
  return Counted{reshaping.ownFields(), 0};
}

} // namespace idr::ownership
