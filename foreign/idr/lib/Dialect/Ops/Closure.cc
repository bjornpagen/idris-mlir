// idr.closure: a function with its leading parameters captured.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// Worlds pass only as arguments and results, never
// in a closure.
LogicalResult ClosureOp::verify() {
  if (llvm::any_of(getCaptures().getTypes(), isWorld))
    return emitOpError("captures a world; a world passes only as an argument or result");
  // A closure holding a linear value is used once as well: applied where
  // it is made, or entered into a linear type, whose one use the linearity
  // check then follows. Any other use could apply it twice.
  if (llvm::none_of(getCaptures().getTypes(),
                    [](Type type) { return quantityOf(type) == Quantity::One; }))
    return success();
  if (getResult().use_empty())
    return success();
  OpOperand &use = *getResult().getUses().begin();
  auto apply = dyn_cast<ApplyOp>(use.getOwner());
  bool linear = getResult().hasOneUse() &&
                (isa<LinEnterOp>(use.getOwner()) || (apply && apply.getCallee() == getResult()));
  if (!linear)
    return emitOpError("captures a linear value, so its one use must apply it or enter it "
                       "into a linear type");
  return success();
}

// The callee's leading parameters are the captures, and the rest of its
// signature is the closure's type.
LogicalResult ClosureOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto fn = symbols.lookupNearestSymbolFrom<func::FuncOp>(*this, getCalleeAttr());
  if (!fn)
    return emitOpError("refers to an unknown function ") << getCalleeAttr();
  ArrayRef<Type> inputs = fn.getArgumentTypes();
  size_t captures = getCaptures().size();
  if (captures > inputs.size() ||
      !llvm::equal(getCaptures().getTypes(), inputs.take_front(captures)))
    return emitOpError("captures ")
           << getCaptures().getTypes() << ", which are not the leading parameters of "
           << getCalleeAttr();
  auto expected = FnType::get(getContext(), inputs.drop_front(captures), fn.getResultTypes());
  if (expected != getType())
    return emitOpError("has type ") << getType() << ", but a closure of " << getCalleeAttr()
                                    << " with these captures is " << expected;
  return success();
}

OpFoldResult ClosureOp::fold(FoldAdaptor adaptor) {
  if (llvm::is_contained(adaptor.getCaptures(), Attribute()))
    return {};
  return ClosureAttr::get(getContext(), getCalleeAttr(),
                          ArrayAttr::get(getContext(), adaptor.getCaptures()));
}
