// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The static data of a program, made in idr-lower's serial phase, before
// any function is lowered: every datum the program's lowering names, each
// made once and kept in the table every function's lowering reads
// (Statics), so the global made for a datum is the one its references name,
// with no name made again to find it: the constants that are static data,
// the atom of every constructor with no field of every family in cells the
// layouts hold, which a constructor or a re-pack names, `nothing` (the cell
// poison of a cell pointer is), the cells of the constant arrays, the texts
// every crash site names, the name of every function whose call keeps an
// account of what it holds, and the thread's cursors of the program's
// homes.

#include "idr/Conversion/Lower/Lower.h"

#include "idr/IR/Families/Families.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Conversion/StaticData.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/AttrTypeSubElements.h"
#include "llvm/ADT/SetVector.h"

#include <algorithm>

using namespace mlir;

namespace idr::conversion {

namespace {

// The static atom of each constructor with no field of each family in
// cells a value of the program is laid out at, and every one their fields
// hold, an array's elements among them, read through the layouts' own
// field types: a re-pack builds a value of a family in cells out of one in
// place wherever a field's slot or a reindex's result is the member at an
// unknown index, so an atom is named wherever any value of its family may
// be, not only where a constructor builds one.
void atoms(ProgramOp program, const Layouts &layouts, StaticData &data) {
  MLIRContext *ctx = program.getContext();
  llvm::SetVector<DataType> found;
  AttrTypeWalker walker;
  walker.addWalk([](FamilyAttr) { return WalkResult::skip(); });
  walker.addWalk([&](DataType type) {
    found.insert(type.unrefined());
    return WalkResult::advance();
  });
  program->walk([&](Operation *op) {
    walker.walk(op->getAttrDictionary());
    for (Type type : op->getResultTypes())
      walker.walk(type);
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (Type type : block.getArgumentTypes())
          walker.walk(type);
  });
  for (size_t at = 0; at < found.size(); ++at) {
    DataType type = found[at];
    if (families::isNumber(type.layout()))
      continue;
    for (uint32_t t = 0, n = type.declaredCount(); t < n; ++t) {
      for (Type field : layouts.fieldTypes(type, Tag{t}))
        walker.walk(field);
      if (type.layout() == Layout::Cell && !type.memo() &&
          layouts.cells(type).cell(Tag{t}).fields.empty())
        data.constant(ConAttr::get(ctx, type.refinedTo(Tag{t}, {}), ArrayAttr::get(ctx, {})),
                      type);
    }
  }
}

} // namespace

FailureOr<Statics> makeStatics(ProgramOp program, const Layouts &layouts) {
  StaticData data(program, layouts, HeaderLayout::of(layouts, program.getContext()).bytes);
  atoms(program, layouts, data);
  program.walk(
      [&](ConstantOp constant) { data.constant(constant.getValue(), constant.getType()); });
  // Every op that can crash says where (CrashSiteOpInterface): a crash, a
  // guard, an exit whose status no parent can read.
  program.walk([&](CrashSiteOpInterface crash) { data.site(crash.getSite()); });
  uint32_t homes = 0;
  program.walk([&](LifetimeHomeOp home) {
    lifetimes::kindOf(home.getOpened())
        .fold([] {}, [] {}, [] {}, [&](uint32_t site) { homes = std::max(homes, site + 1); });
  });
  for (auto fn : program->getRegion(0).getOps<FuncOp>())
    if (fn.getFrameBound() != 0)
      data.account(fn.getSymNameAttr());
  for (auto global : program->getRegion(0).getOps<memref::GlobalOp>()) {
    FailureOr<ConstantArray> array = ConstantArray::of(global);
    if (failed(array))
      return failure();
    data.constantArray(*array);
  }
  data.homes(homes);
  return std::move(data).made();
}

} // namespace idr::conversion
