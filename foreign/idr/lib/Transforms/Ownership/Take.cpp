// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Taking a value apart: a box where it dies, a scrutinee where a case
// region begins, an unboxed sum where it is defined; and whether a take
// where a box dies saves anything over a drop. A take's results are its
// op's to infer from the value and the constructor.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/iterator.h"

using namespace mlir;

namespace idr::ownership {

namespace {

SmallVector<OpOperand *> usesOf(Value value) {
  return llvm::to_vector(llvm::make_pointer_range(value.getUses()));
}

} // namespace

// A field read after the box dies keeps the box's reference instead of
// taking one of its own where the box reads it, only for the box to drop
// it again. Reads before the take are borrowed from the box, which is
// still alive there.
TakeOp takeAt(RewriterBase &rewriter, Value box, Tag tag, Block &block, Block::iterator at,
              ArrayRef<BlockArgument> bound) {
  rewriter.setInsertionPoint(&block, at);
  Location loc = at == block.end() ? block.getParentOp()->getLoc() : at->getLoc();
  auto take = TakeOp::create(rewriter, loc, box, tag);
  for (Field field : fieldsOf(usesOf(box), tag, bound))
    rewriter.replaceUsesWithIf(field.value, take.getFields()[field.index],
                               [&](OpOperand &use) { return heldIn(block, use, at) != nullptr; });
  return take;
}

void takeAtEntry(RewriterBase &rewriter, MatchOp match, unsigned index) {
  Block &block = match.getCaseRegion(index).front();
  Value value = match.getScrutinee();
  Tag tag = match.getCaseTag(index);
  rewriter.setInsertionPointToStart(&block);
  // A constructor with a cell of its own is taken out of the cell, whose
  // token the take gives; any other constructor's value, an unboxed sum or
  // an atom, is its fields already (S36: a cell or none).
  ResultRange fields = buildsCell(value.getType(), tag)
                           ? TakeOp::create(rewriter, match.getLoc(), value, tag).getFields()
                           : UnpackOp::create(rewriter, match.getLoc(), value, tag).getFields();
  rewriter.replaceAllUsesWith(block.getArguments(), fields);
}

void takeFields(RewriterBase &rewriter, Value value, Tag tag) {
  rewriter.setInsertionPointAfterValue(value);
  auto unpack = UnpackOp::create(rewriter, value.getLoc(), value, tag);
  for (Operation *user : llvm::make_early_inc_range(value.getUsers()))
    if (auto read = dyn_cast<FieldOp>(user))
      rewriter.replaceOp(read, unpack.getFields()[read.getIndex()]);
}

// Only where a field that holds references lives on past the point does a
// take there save anything over a drop: a field that lives on moves out of an
// unshared cell instead of taking a reference of its own while the box
// drops the cell's. A field that dies with the box is dropped either way,
// and one that holds no reference has nothing to move.
bool keepsCountedField(Value box, Tag tag, Block &block, Block::iterator at,
                       ArrayRef<BlockArgument> bound) {
  return llvm::any_of(fieldsOf(usesOf(box), tag, bound), [&](Field field) {
    return holdsReferences(field.value.getType()) &&
           llvm::any_of(field.value.getUses(),
                        [&](OpOperand &use) { return heldIn(block, use, at) != nullptr; });
  });
}

} // namespace idr::ownership
