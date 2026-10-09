// idr.field: a field of a constructor value.

#include "idr/Idr.h"

#include "mlir/IR/Matchers.h"

using namespace mlir;
using namespace idr;

// A box is a cell: building one allocates, and reading a field of one
// loads from a cell only as large as its own constructor. A sum is its
// slots, all there whatever its constructor: building or reading it is
// computing, which may run anywhere.
Speculation::Speculatability FieldOp::getSpeculatability() {
  return isa<BoxType>(unrestricted(getValue().getType())) ? Speculation::NotSpeculatable
                                                         : Speculation::Speculatable;
}

LogicalResult FieldOp::verifySymbolUses(SymbolTableCollection &symbols) {
  auto data =
      symbols.lookupNearestSymbolFrom<DataOp>(*this, getSumName(getValue().getType()));
  CtorOp ctor = lookupCtor(data, getCtor());
  if (!ctor)
    return emitOpError("refers to an unknown constructor ") << getCtorAttr();
  if (getIndex() >= ctor.getFieldTypes().size())
    return emitOpError("field index out of range");
  // A field is read at the value's grade times its own, as a match binds it.
  Type expected = fieldType(getValue().getType(), ctor.getFieldType(static_cast<unsigned>(getIndex())));
  if (expected != getType())
    return emitOpError("has result ") << getType() << ", but the field of a "
                                      << getValue().getType() << " is read as " << expected;
  return success();
}

// A field of a known constructor, built by idr.con or constant, also when
// it passed a linear position on the way. A linear field moves out of the
// constructor, so only the constructor's one read takes it: otherwise it
// would be used twice. A field the constructor was built without
// (idr.dest.pending) has no value until its destination is written, so a
// read of it is not the pending operand: it stays a read of the cell.
OpFoldResult FieldOp::fold(FoldAdaptor adaptor) {
  auto index = static_cast<unsigned>(getIndex());
  Value source = throughLinear(getValue());
  if (auto con = source.getDefiningOp<ConOp>())
    if (con.getCtor().getLeafReference() == getCtorAttr().getAttr()) {
      // A field read at another grade than the constructor took it is
      // the canonicalizer's, which holds it as read.
      Value field = con.getFields()[index];
      if (!field.getDefiningOp<PendingOp>() && field.getType() == getType() &&
          (quantityOf(field.getType()) != Quantity::One || fieldReadOnce(con.getResult(), index)))
        return field;
    }
  // The constant is the operand's, as folding or constant propagation knows
  // it, or the one it passed a linear position from.
  auto con = dyn_cast_or_null<ConAttr>(adaptor.getValue());
  if (!con)
    matchPattern(source, m_Constant(&con));
  if (con && con.getCtor().getLeafReference() == getCtorAttr().getAttr()) {
    // One field of the first cell, read in place: off a run's spine that
    // costs nothing however long the run is, where listing every field
    // would build the rest of the run. A run's cells hold all the fields
    // but the spine.
    size_t count = con.getCells().front().size() + (con.isRun() ? 1u : 0u);
    if (index < count)
      return con.getField(index);
  }
  return {};
}
