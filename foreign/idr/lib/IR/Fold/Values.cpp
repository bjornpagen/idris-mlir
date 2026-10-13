// An op's constants as the runtime takes them, and the runtime's results as
// constants: integers, comparisons, a call of a big operation on two
// constants, and the elements of a constant list.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Fold.h"

#include "idris_rt.h"

#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/MLIRContext.h"
#include "llvm/ADT/APInt.h"

using namespace mlir;

namespace idr::fold {

int64_t extended(IntegerAttr value, bool isSigned) {
  return isSigned ? value.getValue().getSExtValue()
                  : static_cast<int64_t>(value.getValue().getZExtValue());
}

Attribute wrapped(Type type, int64_t value) {
  unsigned width = type.getIntOrFloatBitWidth();
  return IntegerAttr::get(type, APInt(width, static_cast<uint64_t>(value), /*isSigned=*/false,
                                      /*implicitTrunc=*/true));
}

Attribute compared(MLIRContext *ctx, CmpPredicate predicate, int32_t order) {
  bool holds = false;
  switch (predicate) {
  case CmpPredicate::eq:
    holds = order == 0;
    break;
  case CmpPredicate::lt:
    holds = order < 0;
    break;
  case CmpPredicate::lte:
    holds = order <= 0;
    break;
  case CmpPredicate::gt:
    holds = order > 0;
    break;
  case CmpPredicate::gte:
    holds = order >= 0;
    break;
  }
  return BoolAttr::get(ctx, holds);
}

OpFoldResult bigBinary(MLIRContext *ctx, Attribute lhs, Attribute rhs, BigOp op) {
  auto a = dyn_cast_or_null<BigAttr>(lhs), b = dyn_cast_or_null<BigAttr>(rhs);
  if (!a || !b)
    return {};
  Scope scope(ctx);
  return scope.attr(op(scope.big(a), scope.big(b)));
}

std::optional<SmallVector<Attribute>> listElements(Attribute list) {
  SmallVector<Attribute> elements;
  while (true) {
    auto con = dyn_cast_or_null<ConAttr>(list);
    if (!con)
      return std::nullopt;
    if (con.isRun()) {
      // Each cell holds the constructor's fields but the spine.
      if (con.getRunCells().front().size() != 1)
        return std::nullopt;
      if (con.getSpine() == 1) {
        for (ArrayAttr cell : con.getRunCells())
          elements.push_back(cell[0]);
        list = con.getTail();
      } else {
        // Along the first field the run is this cell's element, a list
        // whose first element is a list again; the rest is off the spine.
        elements.push_back(con.getField(0));
        list = con.getField(1);
      }
      continue;
    }
    ArrayAttr fields = con.getFields();
    if (fields.empty())
      return elements;
    if (fields.size() != 2)
      return std::nullopt;
    elements.push_back(fields[0]);
    list = fields[1];
  }
}

} // namespace idr::fold
