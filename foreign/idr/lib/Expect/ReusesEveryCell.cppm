// reuses-every-cell: every cell a take yields for a constructor with fields
// is reused, not freed.
export module idr.expect:reusesEveryCell;

import idr.mlir;
import idr.dialect;

import :named;
import :report;

using namespace mlir;

namespace idr::expect {

// In the function the argument names, every cell a take yields
// for a constructor with fields is reused: no idr.drop frees one.
export LogicalResult reusesEveryCell(ModuleOp module, StringRef function) noexcept {
  constexpr StringRef property = "reuses-every-cell";
  SmallVector<func::FuncOp> functions = named(module, function, property);
  if (functions.empty())
    return failure();
  bool held = true;
  for (func::FuncOp fn : functions)
    fn.walk([&](DropOp dec) {
      auto take = dec.getValue().getDefiningOp<TakeOp>();
      if (!take || dec.getValue() != take.getToken())
        return;
      SymbolRefAttr ctor = take.getCtor();
      // A constructor without fields is a static cell, never the program's
      // to reuse.
      if (CtorOp decl = lookupCtor(dec, ctor); decl && decl.getFieldTypes().empty())
        return;
      fail(dec.getLoc(), property) << "the cell of " << ctor << " is freed, not reused, in "
                                   << where(dec);
      held = false;
    });
  return success(held);
}

} // namespace idr::expect
