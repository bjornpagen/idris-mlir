// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where a value is used, and where it dies on each path of a block: what
// reset/reuse insertion decides by, and what explicit counting places by.
#include "idr/Analysis/Ownership.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Operation.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/iterator.h"

#include <algorithm>

using namespace mlir;

namespace idr::ownership {

namespace {

// The ops that hold `uses` in `block` after `after`, in order, once each.
template <typename Uses>
SmallVector<Operation *> holders(Uses &&uses, Block &block, Operation *after) {
  SmallVector<Operation *> users;
  for (OpOperand &use : uses)
    if (Operation *top = heldIn(block, use, after))
      users.push_back(top);
  llvm::sort(users, [](Operation *a, Operation *b) { return a->isBeforeInBlock(b); });
  users.erase(std::unique(users.begin(), users.end()), users.end());
  return users;
}

} // namespace

Operation *heldIn(Block &block, OpOperand &use, Operation *after) {
  Operation *top = block.findAncestorOpInBlock(*use.getOwner());
  if (top && (!after || after->isBeforeInBlock(top)))
    return top;
  return nullptr;
}

SmallVector<Operation *> usersIn(Value value, Block &block, Operation *after) {
  return holders(value.getUses(), block, after);
}

SmallVector<Operation *> usersIn(ArrayRef<OpOperand *> uses, Block &block, Operation *after) {
  return holders(llvm::make_pointee_range(uses), block, after);
}

bool usedAfter(Value value, Operation *op) {
  Block *home = value.getParentBlock();
  for (Operation *at = op; at; at = at->getParentOp()) {
    Block *block = at->getBlock();
    if (!block)
      return false;
    // A use later in this block, or inside an op that is: the uses usersIn
    // lists after `at`.
    if (!usersIn(value, *block, at).empty())
      return true;
    if (block == home || isa<FuncOp>(block->getParentOp()))
      return false;
    // The body of a loop runs again: the next iteration uses the value.
    if (isIndexLoop(block->getParentOp()))
      return true;
  }
  return false;
}

// A last use that consumes the value is where it moves on, its cell with
// it: a take after that use would keep a second reference alive across it,
// so that whoever receives the value finds its cell shared and copies it.
void whereDies(ArrayRef<OpOperand *> uses, Block &block, SymbolTable *graded,
               function_ref<void(Block &, Block::iterator)> at) {
  SmallVector<Operation *> users = usersIn(uses, block, nullptr);
  if (users.empty()) {
    at(block, block.begin());
    return;
  }
  Operation *last = users.back();
  if (last->hasTrait<OpTrait::IsTerminator>())
    return;
  // Before borrow inference every call may still consume its arguments.
  if (!graded && isa<CallOp>(last))
    return;
  if (llvm::any_of(uses, [&](OpOperand *use) {
        return use->getOwner() == last && consumes(*use, graded);
      }))
    return;
  // The body of a loop over indices runs once per index, and a value from
  // outside it is alive throughout: the value dies after the loop.
  if (last->getNumRegions() != 0 && !isIndexLoop(last)) {
    for (Region &region : last->getRegions())
      if (!region.empty())
        whereDies(uses, region.front(), graded, at);
    return;
  }
  at(block, std::next(last->getIterator()));
}

void whereDies(Value value, Block &block, SymbolTable *graded,
               function_ref<void(Block &, Block::iterator)> at) {
  SmallVector<OpOperand *> uses = llvm::to_vector(llvm::make_pointer_range(value.getUses()));
  whereDies(uses, block, graded, at);
}

// heldIn answers "strictly after an op", so the op before `at` (anywhere,
// when `at` is the block's start).
bool fromPoint(Block &block, Block::iterator at, OpOperand &use) {
  if (at == block.end())
    return false;
  Operation *after = at == block.begin() ? nullptr : &*std::prev(at);
  return heldIn(block, use, after);
}

void eachField(ArrayRef<OpOperand *> uses, DataType data, unsigned tag, Block *fields,
               function_ref<void(Value, unsigned)> f) {
  if (fields)
    for (BlockArgument arg : fields->getArguments())
      f(arg, arg.getArgNumber());
  // A constructor's name is unique within its type's body.
  mlir::StringAttr name = data.getCtor(tag).name;
  for (OpOperand *use : uses)
    if (auto read = dyn_cast<FieldOp>(use->getOwner());
        read && read.getCtorAttr().getAttr() == name)
      f(read.getResult(), static_cast<unsigned>(read.getIndex()));
}

FieldOp onlyReads(Value box) {
  if (!isa<BoxType>(unrestricted(box.getType())) || box.use_empty())
    return nullptr;
  SmallVector<OpOperand *> uses = llvm::to_vector(llvm::make_pointer_range(box.getUses()));
  return onlyReads(box.getType(), uses);
}

// A nested pattern reads the fields of a box an outer one matched.
FieldOp onlyReads(Type type, ArrayRef<OpOperand *> uses) {
  if (!isa<BoxType>(unrestricted(type)) || uses.empty())
    return nullptr;
  FieldOp first;
  for (OpOperand *use : uses) {
    auto read = dyn_cast<FieldOp>(use->getOwner());
    if (!read || (first && read.getCtorAttr() != first.getCtorAttr()))
      return nullptr;
    if (!first || (read->getBlock() == first->getBlock() && read->isBeforeInBlock(first)))
      first = read;
  }
  // Every use is in the first read's block, at it or after it: from there
  // on the constructor is known. The uses in the block are usersIn's; one
  // before the first read makes that list longer than the uses at the
  // first read or after it, and a use outside the block is in neither.
  Block *block = first->getBlock();
  Operation *before = first->getPrevNode();
  if (usersIn(uses, *block, before).size() != usersIn(uses, *block, nullptr).size())
    return nullptr;
  if (llvm::any_of(uses, [&](OpOperand *use) {
        return !block->findAncestorOpInBlock(*use->getOwner());
      }))
    return nullptr;
  return first;
}

} // namespace idr::ownership
