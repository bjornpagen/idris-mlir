// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-lower-statics: every static datum the program's lowering names, made
// once, serially, before any function is lowered, each under the name of
// its content (StaticNames), which the lowering's reference to it reads:
// the constants that are static data, the atom a constructor of a cell
// with no field is, `nothing` (the cell poison of a cell pointer is), the
// cells of the constant arrays, the texts every crash site names, and the
// thread's cursors of the program's homes.

#include "Lower.h"

#include "idr/IR/Grades.h"
#include "idr/IR/Lifetimes.h"
#include "idr/Conversion/Passes.h"
#include "idr/Conversion/StaticData.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/Dialect/MemRef/IR/MemRef.h"
#include "mlir/IR/SymbolTable.h"

#include <algorithm>

namespace idr {
#define GEN_PASS_DEF_IDRLOWERSTATICS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::conversion {

namespace {

// The name of the inherent attribute every op that can crash holds its
// site in: the crash ops', the guards', an exit's. Sites live on several
// families of ops with no interface in common, so they are read here by
// the attribute's own class under that one name.
constexpr StringLiteral siteName = "site";

struct LowerStatics : idr::impl::IdrLowerStaticsBase<LowerStatics> {
  using IdrLowerStaticsBase::IdrLowerStaticsBase;

  void runOnProgram(ProgramOp program) {
    MLIRContext *ctx = &getContext();
    const Layouts &layouts = getAnalysis<Layouts>();
    SymbolTable symbols(program);
    StaticData data(program, symbols, layouts, HeaderLayout::of(layouts, ctx).bytes);
    // Poison of a cell pointer may stand anywhere a function is lowered.
    data.nothing();
    uint32_t homes = 0;
    program.walk([&](Operation *op) {
      if (auto constant = dyn_cast<ConstantOp>(op))
        data.constant(constant.getValue(), constant.getType());
      if (auto con = dyn_cast<DataConOp>(op);
          con && con.getFields().empty() && con.getDataType().layout() == Layout::Cell)
        data.constant(ConAttr::get(ctx, cast<DataType>(unrestricted(con.getResult().getType())),
                                   ArrayAttr::get(ctx, {})),
                      con.getResult().getType());
      if (auto site = dyn_cast_or_null<SiteAttr>(op->getInherentAttr(siteName).value_or(nullptr))) {
        data.text(StringRef(site.getFile()));
        data.text(StringRef(site.getFunction()));
      }
      if (auto home = dyn_cast<LifetimeHomeOp>(op))
        cast<LifetimeType>(home.getBody().front().getArgument(0).getType())
            .getKind()
            .fold([] {}, [] {}, [] {}, [&](uint32_t site) { homes = std::max(homes, site + 1); });
    });
    for (auto global : program->getRegion(0).getOps<memref::GlobalOp>()) {
      FailureOr<ConstantArray> array = ConstantArray::of(global);
      if (failed(array))
        return signalPassFailure();
      data.constantArray(*array);
    }
    data.homes(homes);
    markAnalysesPreserved<Layouts>();
  }
};

} // namespace

} // namespace idr::conversion
