// idr.ops:untyped: the form in which idr.constant stores its values.
export module idr.ops:untyped;

import idr.mlir;
import idr.dialect;

using namespace mlir;
using namespace idr;

export namespace idr::ops {

// A value without the type that MLIR's parser reads into it (Idr_Attr): the
// form in which values are stored. A run is rebuilt from its cells and its
// tail in one step, not a cell at a time.
Attribute untyped(Attribute value) {
  MLIRContext *ctx = value.getContext();
  return TypeSwitch<Attribute, Attribute>(value)
      .Case([&](ConAttr con) {
        if (con.isRun())
          return ConAttr::getRun(ctx, con.getCtor(), con.getSpine(), con.getRunCells(),
                                 con.getTail());
        return ConAttr::get(ctx, con.getCtor(), con.getFields());
      })
      .Case([&](ClosureAttr closure) {
        return ClosureAttr::get(ctx, closure.getCallee(), closure.getCaptures());
      })
      .Case([&](BigAttr big) { return BigAttr::get(ctx, big.getValue()); })
      .Case([&](ErasedAttr) { return ErasedAttr::get(ctx); })
      .Case([&](StringAttr str) { return StringAttr::get(ctx, str.getValue()); })
      .Default([](Attribute other) { return other; });
}

} // namespace idr::ops
