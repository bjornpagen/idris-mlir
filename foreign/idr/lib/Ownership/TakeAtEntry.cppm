// idr.ownership:takeatentry: taking a scrutinee apart where a case region
// begins.
export module idr.ownership:takeatentry;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

// Takes the scrutinee of `match` apart where its case region `index`
// begins: an idr.take whose fields replace the region's arguments.
export TakeOp takeAtEntry(MatchOp match, unsigned index) {
  Block &block = match.getCaseRegion(index).front();
  Value value = match.getScrutinee();
  auto data = getSumName(value.getType());
  auto ctor = SymbolRefAttr::get(data.getAttr(), {cast<FlatSymbolRefAttr>(match.getCases()[index])});
  SymbolTableCollection symbols;
  SmallVector<Type> results;
  // A constructor without fields is its atom, which is nobody's to build in.
  if (isa<BoxType>(unrestricted(value.getType())) && block.getNumArguments() != 0)
    results.push_back(owned(TokenType::get(match.getContext())));
  for (Type field : block.getArgumentTypes())
    results.push_back(holdsReferences(field, symbols, match) ? owned(field) : field);
  OpBuilder b = OpBuilder::atBlockBegin(&block);
  auto take = TakeOp::create(b, match.getLoc(), results, value, ctor);
  for (auto [field, taken] : llvm::zip_equal(block.getArguments(), take.getFields()))
    field.replaceAllUsesWith(taken);
  return take;
}

} // namespace idr::ownership
