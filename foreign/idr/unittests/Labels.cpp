// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the label solve (idr::Labels) at a call: a closure of @inc
// given to parameter 0 of @call, whose argument the solve reaches by two
// names, the parameter's point and the block argument, which name one node.

#include "idr/Analysis/Labels.h"
#include "idr/IR/FlowEdges.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/AnalysisManager.h"

#include "gtest/gtest.h"

using namespace mlir;

namespace {

TEST(Labels, AParameterIsOneNodeWithItsArgument) {
  MLIRContext ctx;
  ctx.loadDialect<idr::IdrDialect, arith::ArithDialect>();
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(R"mlir(
idr.program @labels root(@Prog.main) stage(higher) types #idr.types<> {
  idr.func @inc(%x: i64) -> i64 attributes {total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  idr.func @call(%f: !idr.fn<(i64) -> (i64)>, %x: i64) -> i64 attributes {total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %y : i64
  }
  idr.func @Prog.main() -> i64 {
    %f = idr.closure @inc() : () -> !idr.fn<(i64) -> (i64)>
    %c = arith.constant 41 : i64
    %r = idr.call @call(%f, %c) : (!idr.fn<(i64) -> (i64)>, i64) -> i64
    return %r : i64
  }
}
)mlir",
                                                             &ctx);
  ASSERT_TRUE(module);
  auto program = *module->getOps<idr::ProgramOp>().begin();
  auto call = SymbolTable::lookupNearestSymbolFrom<idr::FuncOp>(program,
                                                                StringAttr::get(&ctx, "call"));
  ModuleAnalysisManager mam(*module, /*passInstrumentor=*/nullptr);
  AnalysisManager moduleAnalyses = mam;
  AnalysisManager programAnalyses = moduleAnalyses.nest(program);
  const idr::Labels &labels = programAnalyses.getAnalysis<idr::Labels>();
  ArrayAttr inc = ArrayAttr::get(&ctx, {FlatSymbolRefAttr::get(&ctx, "inc")});
  ArrayAttr byPoint =
      labels.labelsOf(idr::FlowPoint::parameter(FlatSymbolRefAttr::get(&ctx, "call"), 0));
  ArrayAttr byArgument = labels.labelsOf(call.getArgument(0));
  EXPECT_EQ(byPoint, inc);
  EXPECT_EQ(byArgument, inc);
}

} // namespace
