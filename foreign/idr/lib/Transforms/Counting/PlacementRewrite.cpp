// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-place's rewrite (Placement.h): what the walk decided, made: the
// takes first, whose parts replace the reads at every later use, then the
// dups that supply a part while its owner lives, the dups of consuming
// uses, and the drops, each after what the rewrite put at its point before
// it; then the dup each element that takes its reference where it is read
// takes there, whose result every use of the element, those just made
// among them, reads from then on; last, the reads every use of which took
// its reference elsewhere go.
#include "idr/Transforms/Counting/Placement.h"

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallBitVector.h"

#include <ranges>

using namespace mlir;

namespace idr::counting::placement {

//===----------------------------------------------------------------------===//
// The rewrite
//===----------------------------------------------------------------------===//

namespace {

// Whether a use by `op` comes after `made`, an op at a point of its block:
// `op` is a later op of that block, or nested in one.
bool after(Operation *made, Operation *op) {
  Operation *ancestor = made->getBlock()->findAncestorOpInBlock(*op);
  return ancestor && ancestor != made && made->isBeforeInBlock(ancestor);
}

} // namespace

// What a part is at `at`: what gave it its reference at a point before
// `at`, or the part itself, a view.
Value Placement::supplied(ValueId part, Operation *at) const {
  for (const auto &[id, value] : partValues)
    if (id == part && (value.getDefiningOp() == at || after(value.getDefiningOp(), at)))
      return value;
  return valueOf(part);
}

void Placement::apply() {
  IRRewriter rewriter(fn->getContext());
  // Every op goes right before its point's position, after what the rewrite
  // already put there.
  auto insertAt = [&](const Where &where) { rewriter.setInsertionPoint(where.block, where.next); };
  // Takes first: the parts they give replace the views at every later use.
  for (TakeSupply &take : takeSupplies) {
    Value owner = valueOf(take.owner);
    insertAt(take.where);
    Location loc = owner.getLoc();
    // The owner, then each part beneath a needed one that is dead here,
    // taken apart in turn at the same point.
    llvm::SmallVector<std::pair<Value, ValueId>, 4> wholes{{owner, take.owner}};
    while (!wholes.empty()) {
      auto [whole, wholeId] = wholes.pop_back_val();
      Tag tag = *knownConstructor(whole.getType());
      Operation *made;
      ValueRange fields;
      Value token;
      if (buildsCell(whole.getType(), tag)) {
        auto taken = CountTakeOp::create(rewriter, loc, whole);
        made = taken;
        fields = taken.getFields();
        token = taken.getToken();
      } else {
        auto unpacked = CountUnpackOp::create(rewriter, loc, whole);
        made = unpacked;
        fields = unpacked.getFields();
      }
      ++takesPlaced;
      // The fields still in the cell, by position: a field given to a part
      // leaves it, and what is left goes with the cell. MLIR numbers an op's
      // results in `unsigned`, so the count of its fields fits one.
      llvm::SmallBitVector left(static_cast<unsigned>(fields.size()), true);
      for (const auto &[index, part] : childrenOf(wholeId)) {
        if (index == ~0u || index >= fields.size())
          continue;
        bool needed = llvm::is_contained(take.parts, part);
        bool beneath = llvm::any_of(take.parts, [&](ValueId p) {
          for (std::optional<ValueId> up = readFromOf[p]; up; up = readFromOf[*up])
            if (*up == part)
              return true;
          return false;
        });
        if (!needed && !beneath)
          continue;
        if (!left.test(index)) {
          // A second read of one field takes a dup of the first.
          dupSupplies.push_back({take.where, part});
          continue;
        }
        left.reset(index);
        Value field = fields[index];
        if (needed) {
          Value view = valueOf(part);
          rewriter.replaceUsesWithIf(view, field,
                                     [&](OpOperand &use) { return after(made, use.getOwner()); });
          partValues.emplace_back(part, field);
        } else {
          wholes.emplace_back(field, part);
        }
      }
      // The fields nothing needs are dropped, and the emptied cell freed,
      // unless only the end lies ahead.
      if (take.ahead == Ahead::Allocation) {
        for (unsigned index : left.set_bits())
          if (Value field = fields[index]; freedBy(field.getType(), Release::Counted)) {
            CountDropOp::create(rewriter, loc, field);
            ++dropsPlaced;
          }
        if (token)
          TokenFreeOp::create(rewriter, loc, token);
      }
    }
  }
  // Dups that supply a part while its owner lives. The list grows as the
  // takes find a field read twice, so it is walked by index.
  for (std::size_t at = 0; at < dupSupplies.size(); ++at) {
    DupSupply supply = dupSupplies[at];
    Value view = valueOf(supply.part);
    insertAt(supply.where);
    auto dup = CountDupOp::create(rewriter, view.getLoc(), atHold(view.getType(), Hold::counted()), view);
    rewriter.replaceUsesWithIf(view, dup.getResult(), [&](OpOperand &use) {
      return use.getOwner() != dup && after(dup, use.getOwner());
    });
    partValues.emplace_back(supply.part, dup.getResult());
    ++dupsPlaced;
  }
  // Dups for the consuming uses of a value still needed later, or of a part
  // while its owner lives.
  for (DupAt &at : dups) {
    OpOperand &operand = at.user->getOpOperand(at.operand);
    Value value = operand.get();
    rewriter.setInsertionPoint(at.user);
    auto dup = CountDupOp::create(rewriter, at.user->getLoc(), atHold(value.getType(), Hold::counted()), value);
    rewriter.modifyOpInPlace(at.user, [&] { operand.set(dup.getResult()); });
    ++dupsPlaced;
  }
  // Drops, after what the rewrite put at their points: of the value a part
  // became where it took its reference.
  for (DropAt &drop : drops) {
    insertAt(drop.where);
    Value value = roles[drop.value] == Role::Part ? supplied(drop.value, &*drop.where.next) : valueOf(drop.value);
    CountDropOp::create(rewriter, value.getLoc(), value);
    ++dropsPlaced;
  }
  // An element takes its reference where it is read: every use of it, the
  // takes, dups and drops placed above included, reads the dup's result.
  for (ValueId id : elementDups) {
    Value element = valueOf(id);
    rewriter.setInsertionPointAfterValue(element);
    auto dup = CountDupOp::create(rewriter, element.getLoc(), atHold(element.getType(), Hold::counted()), element);
    rewriter.replaceAllUsesExcept(element, dup.getResult(), dup);
    ++dupsPlaced;
  }
  // A part read every use of which took its reference elsewhere goes, the
  // reads beneath it first.
  for (ValueId id : count.ids() | std::views::reverse) {
    if (roles[id] != Role::Part)
      continue;
    Value value = valueOf(id);
    if (Operation *def = value.getDefiningOp();
        def && def->use_empty() && effects::whole(def).onlyComputes())
      rewriter.eraseOp(def);
  }
}

} // namespace idr::counting::placement
