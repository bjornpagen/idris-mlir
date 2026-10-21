// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Points in a block, the positions explicit counting places by, and the
// fields a take of a box gives. Where a value is used, and where it dies
// on each path of a block, is Positions' to say (Positions.cpp).
#include "idr/Analysis/Ownership.h"

#include "idr/IR/IdrDialect.h"

using namespace mlir;

namespace idr::ownership {

namespace {

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

SmallVector<Field> fieldsOf(ArrayRef<OpOperand *> uses, Tag tag, ArrayRef<BlockArgument> bound) {
  SmallVector<Field> fields;
  for (BlockArgument arg : bound)
    fields.push_back({arg, arg.getArgNumber()});
  for (OpOperand *use : uses)
    if (auto read = dyn_cast<FieldOp>(use->getOwner()); read && read.getTag() == tag)
      fields.push_back({read.getResult(), static_cast<unsigned>(read.getIndex())});
  return fields;
}

} // namespace idr::ownership
