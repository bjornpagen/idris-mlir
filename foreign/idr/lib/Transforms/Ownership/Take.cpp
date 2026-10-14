// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Taking a value apart: a box where it dies, a scrutinee where a case
// region begins, an unboxed sum where it is defined; and whether a take
// where a box dies saves anything over a drop.
#include "idr/Analysis/Ownership.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Ownership.h"

#include "mlir/IR/BuiltinAttributes.h"
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
Type taken(Type field, Counted &counted) { return counted(field) ? owned(field) : field; }

} // namespace

// A field read after the box dies keeps the box's reference instead of
// taking one of its own where the box reads it, only for the box to drop
// it again. Reads before the take are borrowed from the box, which is
// still alive there.
TakeOp takeAt(RewriterBase &rewriter, Value box, CtorOp ctor, Block &block, Block::iterator at,
              Block *fields, Counted &counted) {
  rewriter.setInsertionPoint(&block, at);
  Location loc = at == block.end() ? block.getParentOp()->getLoc() : at->getLoc();
  auto name = SymbolRefAttr::get(ctor->getParentOfType<DataOp>().getSymNameAttr(),
                                 {FlatSymbolRefAttr::get(ctor.getSymNameAttr())});
  SmallVector<Type> results;
  // A constructor without fields is its atom, which is nobody's to build in.
  if (!ctor.getFieldTypes().empty())
    results.push_back(owned(TokenType::get(ctor.getContext())));
  for (unsigned index = 0, e = static_cast<unsigned>(ctor.getFieldTypes().size()); index < e;
       ++index)
    results.push_back(taken(fieldType(box.getType(), ctor.getFieldType(index)), counted));
  auto take = TakeOp::create(rewriter, loc, results, box, name);
  eachField(usesOf(box), ctor, fields, [&](Value field, unsigned index) {
    rewriter.replaceUsesWithIf(field, take.getFields()[index],
                               [&](OpOperand &use) { return fromPoint(block, at, use); });
  });
  return take;
}

TakeOp takeAtEntry(RewriterBase &rewriter, MatchOp match, unsigned index, Counted &counted) {
  Block &block = match.getCaseRegion(index).front();
  Value value = match.getScrutinee();
  auto data = getSumName(value.getType());
  auto ctor =
      SymbolRefAttr::get(data.getAttr(), {cast<FlatSymbolRefAttr>(match.getCases()[index])});
  SmallVector<Type> results;
  // A constructor without fields is its atom, which is nobody's to build in.
  if (isa<BoxType>(unrestricted(value.getType())) && block.getNumArguments() != 0)
    results.push_back(owned(TokenType::get(match.getContext())));
  for (Type field : block.getArgumentTypes())
    results.push_back(taken(field, counted));
  rewriter.setInsertionPointToStart(&block);
  auto take = TakeOp::create(rewriter, match.getLoc(), results, value, ctor);
  rewriter.replaceAllUsesWith(block.getArguments(), take.getFields());
  return take;
}

TakeOp takeFields(RewriterBase &rewriter, Value value, SymbolRefAttr ctor,
                  ArrayRef<Type> fieldTypes, Counted &counted) {
  rewriter.setInsertionPointAfterValue(value);
  SmallVector<Type> results;
  for (Type field : fieldTypes)
    results.push_back(taken(field, counted));
  auto take = TakeOp::create(rewriter, value.getLoc(), results, value, ctor);
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
bool keepsCountedField(Value box, CtorOp ctor, Block &block, Block::iterator at, Block *fields,
                       Counted &counted) {
  bool kept = false;
  eachField(usesOf(box), ctor, fields, [&](Value field, unsigned) {
    kept = kept || (counted(field.getType()) &&
                    llvm::any_of(field.getUses(),
                                 [&](OpOperand &use) { return fromPoint(block, at, use); }));
  });
  return kept;
}

} // namespace idr::ownership
