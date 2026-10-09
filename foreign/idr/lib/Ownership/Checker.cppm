// idr.ownership:checker: the walk of one function in the owned stage: each
// op, the regions of a match and the body of a loop over an array, on the
// references each value holds (References) and through the scf loops
// idr-tail-loops makes (Loops). Nothing here is exported: verifyOwned runs
// it.
export module idr.ownership:checker;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :counting;
import :loops;
import :reachesonlyatoms;
import :useof;

using namespace mlir;

namespace idr::ownership {

class Checker final : public Loops {
public:
  Checker(Counting &counting, function_ref<layout::Layouts *()> layouts)
      : Loops(counting), layouts(layouts) {}

  LogicalResult check(func::FuncOp fn) {
    Block &entry = fn.getBody().front();
    for (BlockArgument arg : entry.getArguments()) {
      if (tracked(arg))
        define(arg, 1);
      else if (isView(arg))
        owners[arg] = Value();
    }
    return failure(failed(walk(entry)));
  }

private:
  // Walks `block` from the current state. Returns whether its end is
  // reached, or failure after reporting a violation.
  FailureOr<bool> walk(Block &block) override {
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
    if (auto select = dyn_cast<arith::SelectOp>(op); select && tracked(select))
      return op.emitOpError("selects between values that hold references; in the owned "
                            "stage a match does");
    // An exclusive value alone reaches its cells: no view of it (or of
    // what was read from it) takes a reference of its own, and an
    // exclusive constructor is built of exclusive fields, on the heap. A
    // reference of its own is exclusive only to static data that reaches
    // no cell but atoms, which no take hands out (reachesOnlyAtoms): of
    // anything else, the copy shares the original's cells.
    if (auto dup = dyn_cast<DupOp>(op)) {
      if (isExclusive(dup.getType()) && !reachesOnlyAtoms(dup.getValue()))
        return fail(op, dup.getValue(), "takes an exclusive reference to a value that reaches "
                                        "cells other than atoms, which it shares");
      Value root = viewRoot(dup.getValue());
      if (isExclusive(root.getType()))
        for (OpOperand &use : root.getUses())
          if (!isa<ShareOp>(use.getOwner()) && useOf(use) == Use::Consume)
            return fail(op, root, "takes a reference to a view of an exclusive value, which "
                                  "is then consumed as exclusive (idr.share gives it on as "
                                  "owned)");
    }
    if (isa<ConOp, ReuseOp>(op) && isExclusive(op.getResult(0).getType())) {
      if (op.hasAttr("idr.stack"))
        return op.emitOpError("builds an exclusive value in the stack frame, whose cell is lent");
      for (Value field : op.getOperands()) {
        auto dup = field.getDefiningOp<DupOp>();
        if (isOwned(field.getType()) && !isExclusive(field.getType()) &&
            isa<BoxType, DataType>(unrestricted(field.getType())) &&
            !(dup && reachesOnlyAtoms(dup.getValue())))
          return fail(op, field, "builds an exclusive value of a field that may be shared");
      }
    }
    // A view of an owned value: the one read of it that is not a use. A
    // view at another quantity (entered into a linear type, or used out of
    // one) is a view of the same value.
    if (isa<BorrowOp>(op) || (isa<LinEnterOp, LinUseOp>(op) && isView(op.getOperand(0)))) {
      if (failed(use(op, op.getOperand(0))))
        return failure();
      define(op.getResult(0), 0, op.getOperand(0), /*borrowed=*/true);
      return success();
    }
    // What the op borrows must be alive for all of it, after what it
    // consumes; a loop's terminator passes both on, the views alive as
    // their owners' references move (walkLoop), so its views are checked
    // before its moves. An owned value is consumed, never read directly: a
    // view of it (idr.borrow) is; a view is read, never consumed: a
    // reference of its own (idr.dup) is.
    SmallVector<Value> consumed, borrowed;
    for (OpOperand &operand : op.getOpOperands()) {
      Value value = operand.get();
      bool consumes = useKind(operand) == Use::Consume;
      if (tracked(value)) {
        if (!consumes)
          return fail(op, value, "reads an owned value; only a view of it (idr.borrow) is read");
        consumed.push_back(value);
      } else if (isView(value)) {
        if (consumes)
          return fail(op, value, "consumes a view, which holds no reference; a reference of "
                                 "its own (idr.dup) is consumed");
        borrowed.push_back(value);
      }
    }
    bool passesOn = isa<scf::ConditionOp, scf::YieldOp>(op) &&
                    isa_and_nonnull<scf::WhileOp, scf::ForOp>(op.getParentOp());
    if (passesOn)
      for (Value value : borrowed)
        if (failed(use(op, value)))
          return failure();
    for (Value value : consumed)
      if (failed(consume(op, value)))
        return failure();
    if (!passesOn)
      for (Value value : borrowed)
        if (failed(use(op, value)))
          return failure();
    for (Value result : op.getResults()) {
      if (tracked(result)) {
        define(result, 1);
      } else if (isView(result)) {
        if (!isa<FieldOp>(op))
          return fail(op, result, "makes a value that holds references and is not owned; only "
                                  "a read (idr.field, idr.borrow) makes a view");
        define(result, 0, op.getOperand(0), /*borrowed=*/true);
      }
    }
    if (auto reuse = dyn_cast<ReuseOp>(op))
      return fits(reuse);
    return success();
  }

  // What a use does, where a loop's terminator passes on a borrowed slot
  // or a view (walkLoop).
  Use useKind(OpOperand &operand) {
    Operation *op = operand.getOwner();
    Operation *loop = op->getParentOp();
    if (isa_and_nonnull<scf::WhileOp, scf::ForOp>(loop) && isa<scf::ConditionOp, scf::YieldOp>(op)) {
      unsigned slot = operand.getOperandNumber() - (isa<scf::ConditionOp>(op) ? 1 : 0);
      if (slotOwner(loop, slot) || isView(operand.get()))
        return Use::Borrow;
    }
    if (isa<YieldOp>(op) && op->getParentOp() &&
        passedOn.count(op->getParentOp()->getResult(operand.getOperandNumber())))
      return Use::Borrow;
    return useOf(operand);
  }

  // The token of an idr.reuse comes from an idr.take of a cell of the
  // same size.
  LogicalResult fits(ReuseOp reuse) {
    Operation *made = reuse.getToken().getDefiningOp();
    SymbolRefAttr cell = made ? made->getAttrOfType<SymbolRefAttr>("ctor") : nullptr;
    if (!isa_and_nonnull<TakeOp>(made) || !cell)
      return reuse.emitOpError("builds in a token that no idr.take made");
    CtorOp from = lookupCtor(made, cell);
    CtorOp to = lookupCtor(reuse, reuse.getCtor());
    if (!from || !to)
      return success();
    // Without layouts, which say why, there is nothing to compare.
    layout::Layouts *cells = layouts();
    if (!cells)
      return failure();
    unsigned have = cells->box(from).size, need = cells->box(to).size;
    if (have != need)
      return reuse.emitOpError("builds a cell of ")
             << need << " bytes in the " << have << "-byte cell of " << cell;
    return success();
  }

  FailureOr<bool> walkRegions(Operation &op) {
    if (auto match = dyn_cast<MatchOp>(op))
      return walkMatch(op, match.getScrutinee());
    if (auto match = dyn_cast<MatchLitOp>(op))
      return walkMatch(op, match.getScrutinee());
    // A branch on a condition is a match on an i1: idr-narrow versions a
    // loop with one.
    if (auto branch = dyn_cast<scf::IfOp>(op))
      return walkMatch(op, branch.getCondition());
    if (auto loop = dyn_cast<scf::WhileOp>(op))
      return walkLoop(loop);
    if (auto loop = dyn_cast<scf::ForOp>(op))
      return walkFor(loop);
    if (auto loop = dyn_cast<ArrayGenerateOp>(op))
      return walkArrayLoop(op, {{loop.getFill(), true}}, loop.getBody(), loop.getResults());
    if (auto loop = dyn_cast<ArrayFoldOp>(op))
      return walkArrayLoop(op, {{loop.getArray(), false}, {loop.getInit(), true}}, loop.getBody(),
                           loop.getResults());
    return op.emitOpError("has regions, which the owned stage does not know how to count");
  }

  // A loop over an array (idr.array.generate, idr.array.fold): its body
  // runs once per index it covers, takes its arguments owned (the element as
  // array.get gives it, the accumulator as the init moved in), consumes
  // what its yield passes on, and leaves every value from outside as it
  // found it. The results are owned. `operands` are the loop's operands
  // that hold references, each with whether the loop consumes it.
  FailureOr<bool> walkArrayLoop(Operation &op, ArrayRef<std::pair<Value, bool>> operands, Region &body,
                                ValueRange results) {
    for (auto [value, consumed] : operands)
      if (failed(consumed ? consume(op, value) : use(op, value)))
        return failure();
    size_t mark = log.size();
    Block &block = body.front();
    for (BlockArgument arg : block.getArguments())
      if (tracked(arg))
        define(arg, 1);
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
    }
    undo(mark);
    for (Value result : results)
      if (tracked(result))
        define(result, 1);
    return true;
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
        if (isView(field))
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
    for (Value result : op.getResults()) {
      auto it = passedOn.find(result);
      if (it != passedOn.end())
        define(result, 0, it->second, /*borrowed=*/true);
      else if (tracked(result))
        define(result, 1);
    }
    return true;
  }

  function_ref<layout::Layouts *()> layouts;
};

} // namespace idr::ownership
