// idr.ownership:rc: idr-rc's pipeline: every reference made explicit, in
// Lean's order: reset/reuse insertion, borrow inference, then the incs and
// decs. The module is then in the owned stage, which its grades say and the
// verifier checks after every later pass. The pass itself is a plain unit
// (Rc.cc), since its base is TableGen's; it runs this.
export module idr.ownership:rc;

import idr.mlir;
import idr.dialect;
import idr.layout;

import :borrow;
import :counting;
import :counts;
import :exclusive;
import :inownedstage;
import :reuse;

using namespace mlir;

namespace idr::ownership {

// What idr-rc's options turn on.
export struct RcOptions {
  bool reuse;
  bool sink;
};

// What idr-rc did, for its statistics.
export struct RcCounts {
  unsigned takes = 0, reuses = 0, borrowed = 0, dups = 0, drops = 0, exclusive = 0;
};

namespace {

// The references made explicit, up to exclusivity: no symbol changes on the
// way, so the calls find their callees in one table.
LogicalResult place(ModuleOp module, ArrayRef<func::FuncOp> functions, RcOptions options,
                    RcCounts &counts) {
  SymbolTable table(module);
  SymbolScope scope(module, table);
  if (options.reuse) {
    FailureOr<layout::Layouts> layouts = layout::Layouts::of(module);
    if (failed(layouts))
      return failure();
    for (func::FuncOp fn : functions) {
      auto [takes, reuses] = insertResetReuse(fn, *layouts);
      counts.takes += takes;
      counts.reuses += reuses;
    }
  }
  // Borrow inference decides the signatures, which nothing has graded yet.
  Counting deciding(module, /*ownedStage=*/false);
  counts.borrowed += inferBorrows(module, deciding);
  // The signatures are graded from here on: counting reads them.
  Counting counting(module, /*ownedStage=*/true);
  for (func::FuncOp fn : functions) {
    FailureOr<std::pair<unsigned, unsigned>> placed = insertCounts(fn, counting, options.sink);
    if (failed(placed))
      return failure();
    counts.dups += placed->first;
    counts.drops += placed->second;
  }
  return success();
}

} // namespace

// Runs idr-rc on `module` as `options` say, adding what it did to
// `counts`; failure after reporting what it cannot do.
export LogicalResult rc(ModuleOp module, RcOptions options, RcCounts &counts) {
  if (inOwnedStage(module))
    return module.emitError("idr-rc: the module is already in the owned stage");
  SmallVector<func::FuncOp> functions;
  for (auto fn : module.getOps<func::FuncOp>())
    if (!fn.isExternal())
      functions.push_back(fn);
  if (failed(place(module, functions, options, counts)))
    return failure();
  // With every reference explicit, which values hold the only one to
  // their cells is provenance.
  FailureOr<unsigned> exclusive = inferExclusive(module);
  if (failed(exclusive))
    return failure();
  counts.exclusive += *exclusive;
  return success();
}

} // namespace idr::ownership
