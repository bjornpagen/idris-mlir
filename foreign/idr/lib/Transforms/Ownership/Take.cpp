// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Taking a value apart: a box where it dies, a scrutinee where a case
// region begins, an unboxed sum where it is defined; and whether a take
// where a box dies saves anything over a drop.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
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

// What a take gives for a field of type `field`: a reference of its own
// when it holds references.
Type taken(Type field) { return holdsReferences(field) ? owned(field) : field; }

} // namespace

// A field read after the box dies keeps the box's reference instead of
// taking one of its own where the box reads it, only for the box to drop
// it again. Reads before the take are borrowed from the box, which is
// still alive there.
TakeOp takeAt(RewriterBase &rewriter, Value box, DataType data, Tag tag, Block &block,
              Block::iterator at, ArrayRef<BlockArgument> bound) {
  rewriter.setInsertionPoint(&block, at);
  Location loc = at == block.end() ? block.getParentOp()->getLoc() : at->getLoc();
  const Ctor &ctor = data.getCtor(tag);
  SmallVector<Type> results;
  // A constructor without fields is its atom, which is nobody's to build in.
  if (!ctor.fields.empty())
    results.push_back(owned(TokenType::get(box.getContext())));
  for (Type field : ctor.fields)
    results.push_back(taken(fieldType(box.getType(), field)));
  auto take = TakeOp::create(rewriter, loc, results, box, tag);
  for (Field field : fieldsOf(usesOf(box), tag, bound))
    rewriter.replaceUsesWithIf(field.value, take.getFields()[field.index],
                               [&](OpOperand &use) { return heldIn(block, use, at) != nullptr; });
  return take;
}

TakeOp takeAtEntry(RewriterBase &rewriter, MatchOp match, unsigned index) {
  Block &block = match.getCaseRegion(index).front();
  Value value = match.getScrutinee();
  SmallVector<Type> results;
  // A constructor without fields is its atom, which is nobody's to build in.
  if (isa<BoxType>(unrestricted(value.getType())) && block.getNumArguments() != 0)
    results.push_back(owned(TokenType::get(match.getContext())));
  for (Type field : block.getArgumentTypes())
    results.push_back(taken(field));
  rewriter.setInsertionPointToStart(&block);
  auto take = TakeOp::create(rewriter, match.getLoc(), results, value, match.getCaseTag(index));
  rewriter.replaceAllUsesWith(block.getArguments(), take.getFields());
  return take;
}

TakeOp takeFields(RewriterBase &rewriter, Value value, Tag tag, ArrayRef<Type> fieldTypes) {
  rewriter.setInsertionPointAfterValue(value);
  SmallVector<Type> results;
  for (Type field : fieldTypes)
    results.push_back(taken(field));
  auto take = TakeOp::create(rewriter, value.getLoc(), results, value, tag);
  for (Operation *user : llvm::make_early_inc_range(value.getUsers()))
    if (auto read = dyn_cast<FieldOp>(user))
      rewriter.replaceOp(read, take.getFields()[read.getIndex()]);
  return take;
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
