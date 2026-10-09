// idr.con: a constructor, which allocates a box's cell.

#include "idr/Idr.h"

using namespace mlir;
using namespace idr;

// A box's constructor allocates its cell, so CSE never merges two of them;
// an unused one is still dead code (wouldOpBeTriviallyDead). A cell
// idr-stack keeps in its frame (`idr.stack`) is stack memory, the resource
// MLIR's allocas use. In the owned stage the constructor also takes over
// the references of the fields it is given owned, which it reports as a
// free of each: no pass drops or merges it then, since that would leave
// those references held where nothing consumes them.
void ConOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  if (isa<BoxType>(unrestricted(getType()))) {
    SideEffects::DefaultResource *memory =
        (*this)->hasAttr("idr.stack") ? SideEffects::AutomaticAllocationScopeResource::get()
                                      : SideEffects::DefaultResource::get();
    effects.emplace_back(MemoryEffects::Allocate::get(), getOperation()->getOpResult(0), memory);
  }
  consumedEffects(getOperation(), effects);
}

// A box is a cell: building one allocates, and reading a field of one
// loads from a cell only as large as its own constructor. A sum is its
// slots, all there whatever its constructor: building or reading it is
// computing, which may run anywhere, unless it takes an owned field over:
// hoisted out of a branch, it would take a reference on a path that never
// gave it one.
Speculation::Speculatability ConOp::getSpeculatability() {
  if (isa<BoxType>(unrestricted(getType())) ||
      llvm::any_of(getFields(), [](Value field) { return isOwned(field.getType()); }))
    return Speculation::NotSpeculatable;
  return Speculation::Speculatable;
}

LogicalResult ConOp::verifySymbolUses(SymbolTableCollection &symbols) {
  SymbolRefAttr ref = getCtor();
  if (ref.getNestedReferences().size() != 1)
    return emitOpError("expects a constructor reference @T::@C");
  auto data = symbols.lookupNearestSymbolFrom<DataOp>(
      *this, FlatSymbolRefAttr::get(ref.getRootReference()));
  CtorOp ctor = lookupCtor(data, ref.getLeafReference());
  if (!ctor)
    return emitOpError("refers to an unknown constructor ") << ref;
  if (data.getValueType() != unrestricted(getType()))
    return emitOpError("builds ") << ref << " but has type " << getType();
  auto types = ctor.getFieldTypes();
  if (types.size() != getFields().size())
    return emitOpError("expects ") << types.size() << " fields";
  // In the owned stage a field that holds references is owned (or
  // exclusive): it moves into the cell.
  for (auto [expected, value] : llvm::zip(types.getAsValueRange<TypeAttr>(), getFields()))
    if (expected != value.getType() && !(isOwned(value.getType()) && view(value.getType()) == expected))
      return emitOpError("field has type ") << value.getType() << ", expected " << expected;
  return success();
}
