// Taking a value apart: a scrutinee where a case region begins, and an
// unboxed sum whose only uses read its fields.

#include "Ownership/Ownership.h"

using namespace mlir;

namespace idr::ownership {

TakeOp takeAtEntry(MatchOp match, unsigned index) {
  Block &block = match.getCaseRegion(index).front();
  Value value = match.getScrutinee();
  auto data = getSumName(value.getType());
  auto ctor = SymbolRefAttr::get(data.getAttr(), {cast<FlatSymbolRefAttr>(match.getCases()[index])});
  SmallVector<Type> results;
  if (isa<BoxType>(value.getType()))
    results.push_back(TokenType::get(match.getContext()));
  llvm::append_range(results, block.getArgumentTypes());
  OpBuilder b = OpBuilder::atBlockBegin(&block);
  auto take = TakeOp::create(b, match.getLoc(), results, value, ctor);
  for (auto [field, taken] : llvm::zip_equal(block.getArguments(), take.getFields()))
    field.replaceAllUsesWith(taken);
  return take;
}

TakeOp takeFields(Value value, SymbolRefAttr ctor, ArrayRef<Type> fieldTypes) {
  OpBuilder b(value.getContext());
  if (Operation *def = value.getDefiningOp())
    b.setInsertionPointAfter(def);
  else
    b.setInsertionPointToStart(cast<BlockArgument>(value).getOwner());
  auto take = TakeOp::create(b, value.getLoc(), fieldTypes, value, ctor);
  for (OpOperand &use : llvm::make_early_inc_range(value.getUses())) {
    auto read = dyn_cast<FieldOp>(use.getOwner());
    if (!read)
      continue;
    read.getResult().replaceAllUsesWith(take.getFields()[read.getIndex()]);
    read.erase();
  }
  return take;
}

} // namespace idr::ownership
