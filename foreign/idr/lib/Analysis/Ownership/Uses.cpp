// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Where a value is used, and where it dies on each path of a block: what
// reset/reuse insertion decides by, and what explicit counting places by.
// The ops of a block are asked from a first op on, a half-open range whose
// start is the block's own start or the op after another, so no position
// is a special case.
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

// The ops that hold `uses` in `block` from `from` on, in order, once each.
template <typename Uses>
SmallVector<Operation *> holders(Uses &&uses, Block &block, Block::iterator from) {
  SmallVector<Operation *> users;
  for (OpOperand &use : uses)
    if (Operation *top = heldIn(block, use, from))
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

// One case for each kind of point, so a visit of a point has every case.
Block &blockAt(BlockStart at) { return *at.block; }
Block &blockAt(After at) { return *at.op->getBlock(); }
Block::iterator firstAfter(BlockStart at) { return at.block->begin(); }
Block::iterator firstAfter(After at) { return std::next(at.op->getIterator()); }

} // namespace

Block &blockOf(const Point &point) {
  return std::visit([](auto at) -> Block & { return blockAt(at); }, point);
}

Block::iterator firstAt(const Point &point) {
  return std::visit([](auto at) { return firstAfter(at); }, point);
}

Point pointBefore(Block &block, Block::iterator at) {
  if (at == block.begin())
    return BlockStart{&block};
  return After{&*std::prev(at)};
}

Point definedAt(Value value) {
  if (auto arg = dyn_cast<BlockArgument>(value))
    return BlockStart{arg.getOwner()};
  return After{value.getDefiningOp()};
}

Operation *heldIn(Block &block, OpOperand &use, Block::iterator from) {
  if (from == block.end())
    return nullptr;
  Operation *top = block.findAncestorOpInBlock(*use.getOwner());
  if (top && (top == &*from || from->isBeforeInBlock(top)))
    return top;
  return nullptr;
}

SmallVector<Operation *> usersIn(Value value, Block &block, Block::iterator from) {
  return holders(value.getUses(), block, from);
}

SmallVector<Operation *> usersIn(ArrayRef<OpOperand *> uses, Block &block, Block::iterator from) {
  return holders(llvm::make_pointee_range(uses), block, from);
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
// there, while another region used it. The ops that hold `op` are its
// ancestors, a chain that ends at the function.
bool usedAfter(Value value, Operation *op) {
  Block *home = value.getParentBlock();
  for (Operation *at = op; at; at = at->getParentOp()) {
    Block *block = at->getBlock();
    if (!block)
      return false;
    if (!usersIn(value, *block, std::next(at->getIterator())).empty())
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
void whereDies(ArrayRef<OpOperand *> uses, Block &block, function_ref<bool(OpOperand &)> takesOver,
               function_ref<void(Block &, Block::iterator)> at) {
  SmallVector<Operation *> users = usersIn(uses, block, block.begin());
  if (users.empty()) {
    at(block, block.begin());
    return;
  }
  Operation *last = users.back();
  if (last->hasTrait<OpTrait::IsTerminator>() ||
      llvm::any_of(uses, [&](OpOperand *use) { return use->getOwner() == last && takesOver(*use); }))
    return;
  // An op that decides moves the value into each of its regions, where it
  // dies on each path; any other holds it for as long as it runs, and it
  // dies after the op.
  if (decides(last)) {
    for (Region &region : last->getRegions())
      if (!region.empty())
        whereDies(uses, region.front(), takesOver, at);
    return;
  }
  at(block, std::next(last->getIterator()));
}

void whereDies(Value value, Block &block, function_ref<bool(OpOperand &)> takesOver,
               function_ref<void(Block &, Block::iterator)> at) {
  SmallVector<OpOperand *> uses = llvm::to_vector(llvm::make_pointer_range(value.getUses()));
  whereDies(uses, block, takesOver, at);
}

SmallVector<Field> fieldsOf(ArrayRef<OpOperand *> uses, Tag tag, ArrayRef<BlockArgument> bound) {
  SmallVector<Field> fields;
  for (BlockArgument arg : bound)
    fields.push_back({arg, arg.getArgNumber()});
  for (OpOperand *use : uses)
    if (auto read = dyn_cast<FieldOp>(use->getOwner()); read && read.getTag() == tag)
      fields.push_back({read.getResult(), static_cast<unsigned>(read.getIndex())});
  return fields;
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
  // before the first read makes the list from the block's start longer
  // than the one from the first read, and a use outside the block is in
  // neither.
  Block *block = first->getBlock();
  if (usersIn(uses, *block, first->getIterator()).size() !=
      usersIn(uses, *block, block->begin()).size())
    return nullptr;
  if (llvm::any_of(uses, [&](OpOperand *use) {
        return !block->findAncestorOpInBlock(*use->getOwner());
      }))
    return nullptr;
  return first;
}

} // namespace idr::ownership
