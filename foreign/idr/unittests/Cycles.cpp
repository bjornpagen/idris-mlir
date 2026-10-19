// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the cycles of calls (idr::CallCycles), as the analysis manager
// caches them, and of what idr-rc's stack step reads of them
// (Escapes::recursive), against reachability: every call graph on
// `functions` functions, with each function's call of itself in tail
// position or not, under a root that calls them all. Two functions are
// together exactly when each reaches the other; a function calls itself
// exactly when it is alone in its component and calls itself; every
// component comes after the components of its callees; and a function is
// recursive exactly when it is on a cycle, its own call of itself in tail
// position (the next iteration of a loop in one frame) aside. The judgement
// is shown failing each oracle planted with a fault.

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

#include <array>
#include <cstdint>
#include <string>

using namespace mlir;

namespace {

constexpr unsigned functions = 3;
using Graph = std::array<std::array<bool, functions>, functions>;

// A graph, read from bits: bit i * functions + j is a call of j by i; and
// which of the functions that call themselves do so in tail position.
struct Case {
  Graph calls{};
  std::array<bool, functions> tail{};
};

std::string name(unsigned i) { return "f" + std::to_string(i); }

// The program of a case: each function calls its callees in order, its own
// call last, and returns their sum with its argument, or, when its call of
// itself is in tail position, that call's result; the root calls every
// function.
std::string programOf(const Case &c) {
  std::string text = "idr.program @cycles root(@Prog.main) stage(first) {\n";
  for (unsigned i = 0; i < functions; ++i) {
    text += "  idr.func @" + name(i) + "(%n: i64) -> i64 {\n";
    std::string sum = "%n";
    unsigned k = 0;
    for (unsigned j = 0; j < functions; ++j) {
      if (!c.calls[i][j] || j == i)
        continue;
      std::string r = "%r" + std::to_string(k), s = "%s" + std::to_string(k);
      text += "    " + r + " = idr.call @" + name(j) + "(%n) : (i64) -> i64\n";
      text += "    " + s + " = arith.addi " + sum + ", " + r + " : i64\n";
      sum = s;
      ++k;
    }
    if (c.calls[i][i]) {
      text += "    %self = idr.call @" + name(i) + "(" + sum + ") : (i64) -> i64\n";
      if (c.tail[i]) {
        sum = "%self";
      } else {
        text += "    %last = arith.addi %self, %n : i64\n";
        sum = "%last";
      }
    }
    text += "    return " + sum + " : i64\n  }\n";
  }
  text += "  idr.func @Prog.main() -> i64 {\n    %c = arith.constant 1 : i64\n";
  for (unsigned i = 0; i < functions; ++i)
    text += "    %m" + std::to_string(i) + " = idr.call @" + name(i) + "(%c) : (i64) -> i64\n";
  text += "    return %c : i64\n  }\n}\n";
  return text;
}

// Reachability through one call or more (Floyd-Warshall's closure).
Graph reaches(const Graph &calls) {
  Graph r = calls;
  for (unsigned k = 0; k < functions; ++k)
    for (unsigned i = 0; i < functions; ++i)
      for (unsigned j = 0; j < functions; ++j)
        r[i][j] = r[i][j] || (r[i][k] && r[k][j]);
  return r;
}

idr::FuncOp function(idr::ProgramOp program, StringRef symbol) {
  return SymbolTable::lookupNearestSymbolFrom<idr::FuncOp>(
      program, StringAttr::get(program.getContext(), symbol));
}

// What a judge takes for the truth: reachability, and whether a function's
// call of itself in tail position makes it recursive. The box's is
// `reaches` and no; a mutant's is wrong, and the judge must say so.
struct Oracle {
  Graph (*reach)(const Graph &);
  bool tailRecurses;
};

// The cases whose analyses disagree with `oracle`, every graph and every
// choice of tail calls, up to `most`; each reported as a failure when
// `report` is set.
unsigned judge(Oracle oracle, unsigned most, bool report) {
  MLIRContext ctx;
  ctx.loadDialect<idr::IdrDialect, arith::ArithDialect>();
  constexpr uint32_t graphs = uint32_t{1} << (functions * functions);
  unsigned failures = 0;
  for (uint32_t bits = 0; bits < graphs && failures < most; ++bits) {
    Case base;
    for (unsigned i = 0; i < functions; ++i)
      for (unsigned j = 0; j < functions; ++j)
        base.calls[i][j] = ((bits >> (i * functions + j)) & 1) != 0;
    // Each function that calls itself does so in tail position or not.
    uint32_t selves = 0;
    for (unsigned i = 0; i < functions; ++i)
      selves |= static_cast<uint32_t>(base.calls[i][i]) << i;
    for (uint32_t tails = selves; failures < most; tails = (tails - 1) & selves) {
      Case c = base;
      for (unsigned i = 0; i < functions; ++i)
        c.tail[i] = ((tails >> i) & 1) != 0;
      std::string text = programOf(c);
      OwningOpRef<ModuleOp> module = parseSourceString<ModuleOp>(text, &ctx);
      // A program the box writes and cannot read is the box's fault, and
      // ends the judgement.
      if (!module) {
        ADD_FAILURE() << "the box's program does not parse\n" << text;
        return failures + 1;
      }
      idr::ProgramOp program = *module->getOps<idr::ProgramOp>().begin();
      ModuleAnalysisManager mam(*module, /*passInstrumentor=*/nullptr);
      AnalysisManager moduleAnalyses = mam;
      AnalysisManager programAnalyses = moduleAnalyses.nest(program);
      const idr::CallCycles &cycles = programAnalyses.getAnalysis<idr::CallCycles>();
      const idr::Escapes &escapes = programAnalyses.getAnalysis<idr::Escapes>();
      std::array<idr::FuncOp, functions> f;
      for (unsigned i = 0; i < functions; ++i)
        f[i] = function(program, name(i));
      idr::FuncOp main = function(program, "Prog.main");
      Graph r = oracle.reach(c.calls);
      auto fail = [&](const std::string &what) {
        ++failures;
        if (report)
          ADD_FAILURE() << what << "\n" << text;
      };
      for (unsigned i = 0; i < functions; ++i) {
        bool alone = true;
        for (unsigned j = 0; j < functions; ++j) {
          bool together = i == j || (r[i][j] && r[j][i]);
          if (i != j && together)
            alone = false;
          if (cycles.together(f[i], f[j]) != together)
            fail("together(" + name(i) + ", " + name(j) + ")");
          if (c.calls[i][j] && !together && cycles.componentOf(f[j]) >= cycles.componentOf(f[i]))
            fail(name(j) + "'s component is not before its caller " + name(i) + "'s");
        }
        if (cycles.callsItself(f[i]) != (alone && c.calls[i][i]))
          fail("callsItself(" + name(i) + ")");
        if (cycles.componentOf(f[i]) >= cycles.componentOf(main))
          fail(name(i) + "'s component is not before the root's");
        bool recursive = !alone || (c.calls[i][i] && (oracle.tailRecurses || !c.tail[i]));
        if (escapes.recursive(f[i]) != recursive)
          fail("recursive(" + name(i) + ")");
      }
      if (cycles.callsItself(main) || escapes.recursive(main))
        fail("the root is on a cycle");
      if (tails == 0)
        break;
    }
  }
  return failures;
}

TEST(CallCycles, EveryGraphAgainstReachability) {
  EXPECT_EQ(judge(Oracle{reaches, false}, 10, /*report=*/true), 0u);
}

// One call, not a chain of them: a cycle through three functions is then
// no cycle.
Graph oneCall(const Graph &calls) { return calls; }

// The judgement can fail: each oracle with a planted fault disagrees with
// the analyses on some case of the box, reachability that stops after one
// call, and a call of itself in tail position taken for recursion.
TEST(CallCycles, EachMutantOracleIsCaught) {
  EXPECT_GT(judge(Oracle{oneCall, false}, 1, /*report=*/false), 0u);
  EXPECT_GT(judge(Oracle{reaches, true}, 1, /*report=*/false), 0u);
}

// A function with no body is a component of its own, on no cycle.
TEST(CallCycles, ADeclarationIsAComponentOfItsOwn) {
  MLIRContext ctx;
  ctx.loadDialect<idr::IdrDialect, arith::ArithDialect, func::FuncDialect>();
  Case c;
  c.calls[0][1] = c.calls[1][0] = true;
  std::string text = programOf(c) + "func.func private @Prog.external(i64) -> i64\n";
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
