// idr.ownership:takefields: taking an unboxed sum apart where it is defined.
export module idr.ownership:takefields;

import idr.mlir;
import idr.dialect;

using namespace mlir;

namespace idr::ownership {

// Takes the unboxed sum `value`, built by `ctor` whose fields have
// `fieldTypes`, apart where it is defined, and gives each of its field
// reads the field taken.
export TakeOp takeFields(Value value, SymbolRefAttr ctor, ArrayRef<Type> fieldTypes) {
  OpBuilder b(value.getContext());
  if (Operation *def = value.getDefiningOp())
    b.setInsertionPointAfter(def);
  else
    b.setInsertionPointToStart(cast<BlockArgument>(value).getOwner());
  SymbolTableCollection symbols;
  SmallVector<Type> results;
  for (Type field : fieldTypes)
    results.push_back(holdsReferences(field, symbols, value.getParentRegion()->getParentOp())
                          ? owned(field)
                          : field);
  auto take = TakeOp::create(b, value.getLoc(), results, value, ctor);
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
