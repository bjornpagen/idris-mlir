// Taking a scrutinee apart where a case region begins.

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

} // namespace idr::ownership
