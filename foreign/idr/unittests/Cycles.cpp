// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// NEEDS-ACCEPTANCE: that CallCycles parts a program's functions into its cycles of calls, callees first, two functions that call each other in one component and a function that calls itself, in tail position or not, alone in one that calls itself; that a declaration is a component of its own on no cycle; and that Escapes::recursive holds of a function on a cycle of calls but not of one whose only call of itself is in tail position.
// The box of the cycles of calls (idr::CallCycles), as the analysis manager
// caches them, and of what idr-rc's stack step reads of them
// (Escapes::recursive): a program of a mutual recursion, a self call in
// tail position, one that is not, a leaf, and a root that calls them all.

#include "idr/Analysis/CallCycles.h"
#include "idr/Analysis/Escapes.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Arith/IR/Arith.h"
#include "mlir/Dialect/Func/IR/FuncOps.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Parser/Parser.h"
#include "mlir/Pass/AnalysisManager.h"

#include "gtest/gtest.h"

#include <string>

using namespace mlir;

namespace {

constexpr StringLiteral cyclesText = R"mlir(
idr.program @cycles root(@Prog.main) stage(first) {
  idr.func @even(%n: i64) -> i64 {
    %r = idr.call @odd(%n) : (i64) -> i64
    return %r : i64
  }
  idr.func @odd(%n: i64) -> i64 {
    %r = idr.call @even(%n) : (i64) -> i64
    return %r : i64
  }
  idr.func @loop(%n: i64) -> i64 {
    %r = idr.call @loop(%n) : (i64) -> i64
    return %r : i64
  }
  idr.func @deep(%n: i64) -> i64 {
    %r = idr.call @deep(%n) : (i64) -> i64
    %s = arith.addi %r, %n : i64
    return %s : i64
  }
  idr.func @leaf(%n: i64) -> i64 {
    return %n : i64
  }
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 1 : i64
    %a = idr.call @even(%c) : (i64) -> i64
    %b = idr.call @leaf(%a) : (i64) -> i64
    %d = idr.call @loop(%b) : (i64) -> i64
    %e = idr.call @deep(%d) : (i64) -> i64
    return %e : i64
  }
}
)mlir";

idr::ProgramOp programOf(ModuleOp module) {
  return *module.getOps<idr::ProgramOp>().begin();
}

idr::FuncOp function(idr::ProgramOp program, StringRef name) {
  return SymbolTable::lookupNearestSymbolFrom<idr::FuncOp>(
      program, StringAttr::get(program.getContext(), name));
}

TEST(CallCycles, MutualSelfAndLeaf) {
  MLIRContext ctx;
  ctx.loadDialect<idr::IdrDialect, arith::ArithDialect>();
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(cyclesText, &ctx);
  ASSERT_TRUE(module);
  idr::ProgramOp prog = programOf(*module);
  ModuleAnalysisManager mam(*module, /*passInstrumentor=*/nullptr);
  AnalysisManager moduleAnalyses = mam;
  AnalysisManager programAnalyses = moduleAnalyses.nest(prog);
  const idr::CallCycles &cycles = programAnalyses.getAnalysis<idr::CallCycles>();
  idr::FuncOp even = function(prog, "even"), odd = function(prog, "odd"),
              loop = function(prog, "loop"), deep = function(prog, "deep"),
              leaf = function(prog, "leaf"), main = function(prog, "Prog.main");
  EXPECT_EQ(cycles.components().size(), 5u);
  EXPECT_EQ(cycles.components()[cycles.componentOf(even)].size(), 2u);
  EXPECT_TRUE(cycles.together(even, odd));
  EXPECT_TRUE(cycles.together(odd, even));
  EXPECT_FALSE(cycles.together(even, leaf));
  EXPECT_TRUE(cycles.callsItself(loop));
  EXPECT_TRUE(cycles.callsItself(deep));
  EXPECT_FALSE(cycles.callsItself(leaf));
  EXPECT_FALSE(cycles.callsItself(even));
  EXPECT_FALSE(cycles.callsItself(main));
  // Callees first.
  for (idr::FuncOp callee : {even, odd, leaf, loop, deep})
    EXPECT_LT(cycles.componentOf(callee), cycles.componentOf(main))
        << callee.getSymName().str();

  const idr::Escapes &escapes = programAnalyses.getAnalysis<idr::Escapes>();
  EXPECT_TRUE(escapes.recursive(even));
  EXPECT_TRUE(escapes.recursive(odd));
  EXPECT_TRUE(escapes.recursive(deep));
  // Its one call of itself is the next iteration of a loop in one frame.
  EXPECT_FALSE(escapes.recursive(loop));
  EXPECT_FALSE(escapes.recursive(leaf));
  EXPECT_FALSE(escapes.recursive(main));
}

// A function with no body is a component of its own, on no cycle.
TEST(CallCycles, ADeclarationIsAComponentOfItsOwn) {
  MLIRContext ctx;
  ctx.loadDialect<idr::IdrDialect, arith::ArithDialect, func::FuncDialect>();
  std::string text = cyclesText.str() + "func.func private @Prog.external(i64) -> i64\n";
  OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(text, &ctx);
  ASSERT_TRUE(module);
  auto external = SymbolTable::lookupNearestSymbolFrom<func::FuncOp>(
      *module, StringAttr::get(&ctx, "Prog.external"));
  ASSERT_TRUE(external);
  ModuleAnalysisManager mam(*module, /*passInstrumentor=*/nullptr);
  AnalysisManager moduleAnalyses = mam;
  const idr::CallCycles &cycles = moduleAnalyses.getAnalysis<idr::CallCycles>();
  unsigned at = cycles.componentOf(external);
  ASSERT_LT(at, cycles.components().size());
  ASSERT_EQ(cycles.components()[at].size(), 1u);
  EXPECT_EQ(cycles.components()[at].front(), external.getOperation());
  EXPECT_FALSE(cycles.callsItself(external));
}

} // namespace
