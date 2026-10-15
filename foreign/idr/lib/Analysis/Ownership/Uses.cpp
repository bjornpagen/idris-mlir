// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where a value is used, and where it dies on each path of a block: what
// reset/reuse insertion decides by, and what explicit counting places by.
#include "idr/Analysis/Ownership.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/Block.h"
#include "mlir/IR/Operation.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
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

// Whether a use of `value` is inside `op`, in one of its regions.
bool usedWithin(Value value, Operation *op) {
  return llvm::any_of(value.getUses(),
                      [&](OpOperand &use) { return op->isProperAncestor(use.getOwner()); });
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

// Its regions are alternatives, as the owned stage's verifier reads them,
// and its entry goes into one of them: an op whose entry may also leave it
// (an scf.if with no else) holds what its region reads, which is what the
// verifier's path around the region asks.
bool decides(Operation *op) {
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  if (!branch || !verify::alternatives(branch))
    return false;
  SmallVector<RegionSuccessor> entries;
  branch.getSuccessorRegions(RegionBranchPoint::parent(), entries);
  return !entries.empty() &&
         llvm::none_of(entries, [](RegionSuccessor s) { return s.isOperation(); });
}

// The reference is there at `op` when the value has a use after the op
// that holds `op` at some level, and inside an op that does not decide
// when that op uses it anywhere inside: it holds the value as long as it
// runs. A use inside an op that decides is no reason: the region that
// holds `op` may have dropped the value on entry, or after its last use
// there, while another region used it.
bool usedAfter(Value value, Operation *op) {
  Block *home = value.getParentBlock();
  for (Operation *at = op; at; at = at->getParentOp()) {
    Block *block = at->getBlock();
    if (!block)
      return false;
    if (!usersIn(value, *block, at).empty())
      return true;
    Operation *parent = block->getParentOp();
    if (block == home || isa<FuncOp>(parent))
      return false;
    if (!decides(parent) && usedWithin(value, parent))
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
  // An op that decides moves the value into each of its regions, where it
  // dies on each path; any other holds it for as long as it runs, and it
  // dies after the op.
  if (decides(last)) {
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

void eachField(ArrayRef<OpOperand *> uses, unsigned tag, Block *fields,
               function_ref<void(Value, unsigned)> f) {
  if (fields)
    for (BlockArgument arg : fields->getArguments())
      f(arg, arg.getArgNumber());
  for (OpOperand *use : uses)
    if (auto read = dyn_cast<FieldOp>(use->getOwner());
        read && static_cast<unsigned>(read.getTag()) == tag)
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
    if (!read || (first && read.getTag() != first.getTag()))
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
