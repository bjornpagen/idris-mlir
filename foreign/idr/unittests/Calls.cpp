// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The box of the program graph (idr::solver::ProgramGraph), the one index
// of a program's calls, against the calls a program was built with. Each
// case is a program of up to four functions built from a seed, each body
// its calls in order, the last of them in tail position or not. Each
// function's row is every distinct callee and tail kind of its calls with
// how many calls have it; its callers are the functions that call it, each
// once; it calls itself exactly when one of its calls names it. Two
// functions share a component exactly when each reaches the other; a
// function is on a cycle exactly when it reaches itself; every component
// comes after those its members call; and the components' members are
// every function once. The judgement is shown failing each model planted
// with a fault.

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Id.h"
#include "idr/Testing/Draws.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinAttributes.h"
#include "mlir/IR/BuiltinOps.h"
#include "mlir/IR/Diagnostics.h"
#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/Verifier.h"
#include "mlir/Pass/AnalysisManager.h"
#include "llvm/ADT/STLExtras.h"

#include "gtest/gtest.h"

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <iterator>
#include <string>
#include <tuple>
#include <utility>
#include <vector>

namespace {

using idr::TailKind;
using idr::box::Draws;
using idr::solver::FunctionId;
using idr::solver::ProgramGraph;

// The number of seeds the box builds a program from, and the most
// functions one holds.
constexpr std::uint64_t seeds = 3000;
constexpr unsigned most = 4;

// A call of a program: its callee's index and where it stands.
struct Call {
  unsigned callee;
  TailKind kind;
};

// A program, as data: each function's calls in order.
using Program = std::vector<std::vector<Call>>;

// The program of a seed: up to as many calls per body as the seed allows,
// to any function, the last in tail position as often as not.
Program programOf(std::uint64_t seed) {
  Draws draws(seed);
  unsigned functions = 1 + draws.below(most);
  unsigned busiest = 1 + draws.below(4);
  Program program(functions);
  for (std::vector<Call> &calls : program) {
    for (unsigned c = draws.below(busiest); c > 0; --c)
      calls.push_back({draws.below(functions), TailKind::nontail});
    const TailKind last[] = {TailKind::nontail, TailKind::tail};
    if (!calls.empty())
      calls.back().kind = last[draws.below(std::size(last))];
  }
  return program;
}

std::string nameOf(unsigned f) { return "f" + std::to_string(f); }

// The IR of `program`, at the first stage, f0 its root: each function
// taking and giving nothing, its body its calls, then its return, so a
// last call in tail position gives its function's return its results.
// Every row is left whole, which says too much and never too little.
mlir::OwningOpRef<mlir::ModuleOp> built(mlir::MLIRContext &context, const Program &program,
                                        std::vector<idr::FuncOp> &functions) {
  mlir::OpBuilder b(&context);
  mlir::Location loc = b.getUnknownLoc();
  mlir::OwningOpRef<mlir::ModuleOp> module = mlir::ModuleOp::create(loc);
  b.setInsertionPointToEnd(module->getBody());
  auto top = idr::ProgramOp::create(b, loc, "calls", nameOf(0), idr::Stage::First);
  b.setInsertionPointToEnd(&top.getBody().front());
  for (unsigned f = 0; f < program.size(); ++f) {
    mlir::OperationState state(loc, idr::FuncOp::getOperationName());
    auto &properties = state.getOrAddProperties<idr::FuncOp::Properties>();
    properties.sym_name = b.getStringAttr(nameOf(f));
    properties.function_type = mlir::TypeAttr::get(b.getFunctionType({}, {}));
    state.addRegion();
    functions.push_back(llvm::cast<idr::FuncOp>(b.create(state)));
  }
  for (unsigned f = 0; f < program.size(); ++f) {
    b.createBlock(&functions[f].getBody());
    for (Call call : program[f])
      idr::CallOp::create(b, loc, functions[call.callee], idr::IndexArgsAttr(), mlir::ValueRange(),
                          call.kind);
    idr::ReturnOp::create(b, loc, mlir::ValueRange());
  }
  return module;
}

// A row of the graph or of a model: a callee, a kind and its count of
// calls, in one order.
using Row = std::vector<std::tuple<unsigned, TailKind, std::uint32_t>>;

// What a judge takes for the truth of a program: each function's row,
// and reachability through one call or more. The box's is read off the
// calls; a mutant's is wrong, and the judge must say so.
struct Model {
  std::vector<Row> rows;
  std::array<std::array<bool, most>, most> reaches{};
};

Model truth(const Program &program) {
  Model model;
  unsigned n = static_cast<unsigned>(program.size());
  for (unsigned f = 0; f < n; ++f) {
    Row row;
    for (Call call : program[f]) {
      auto same = llvm::find_if(row, [&](const auto &entry) {
        return std::get<0>(entry) == call.callee && std::get<1>(entry) == call.kind;
      });
      if (same == row.end())
        row.emplace_back(call.callee, call.kind, 1);
      else
        ++std::get<2>(*same);
      model.reaches[f][call.callee] = true;
    }
    std::ranges::sort(row);
    model.rows.push_back(std::move(row));
  }
  for (unsigned k = 0; k < n; ++k)
    for (unsigned i = 0; i < n; ++i)
      for (unsigned j = 0; j < n; ++j)
        model.reaches[i][j] = model.reaches[i][j] || (model.reaches[i][k] && model.reaches[k][j]);
  return model;
}

using Oracle = Model (*)(const Program &);

std::string describe(const Program &program) {
  std::string text;
  for (unsigned f = 0; f < program.size(); ++f) {
    text += "\n  " + nameOf(f) + ":";
    for (Call call : program[f])
      text += " " + nameOf(call.callee) + (call.kind == TailKind::tail ? "(tail)" : "");
  }
  return text;
}

// Whether a failing case is reported: by the box's own judgement, each;
// by a mutant's, none, since a mutant must fail.
enum class Report : std::uint8_t { Each, None };

// The cases, over every seed up to `limit` of them, whose graph disagrees
// with `oracle`, or that do not verify.
template <Oracle oracle>
unsigned judge(unsigned limit, Report report) {
  mlir::MLIRContext context;
  context.disableMultithreading();
  context.loadDialect<idr::IdrDialect>();
  std::string diagnostic;
  mlir::ScopedDiagnosticHandler capture(&context, [&](mlir::Diagnostic &found) {
    if (diagnostic.empty())
      diagnostic = found.str();
    return mlir::success();
  });
  unsigned failures = 0;
  for (std::uint64_t seed = 1; seed <= seeds && failures < limit; ++seed) {
    Program program = programOf(seed);
    std::vector<idr::FuncOp> functions;
    diagnostic.clear();
    mlir::OwningOpRef<mlir::ModuleOp> module = built(context, program, functions);
    std::string why;
    auto fail = [&](const std::string &what) { why += "\n  " + what; };
    if (mlir::failed(mlir::verify(*module))) {
      fail("the program does not verify: " + diagnostic);
    } else {
      Model model = oracle(program);
      mlir::ModuleAnalysisManager modules(*module, /*passInstrumentor=*/nullptr);
      mlir::AnalysisManager analyses = modules;
      const ProgramGraph &graph =
          analyses.nest(*module->getOps<idr::ProgramOp>().begin()).getAnalysis<ProgramGraph>();
      unsigned n = static_cast<unsigned>(program.size());
      std::vector<FunctionId> ids;
      for (idr::FuncOp fn : functions)
        ids.push_back(graph.id(fn));
      auto indexOf = [&](FunctionId id) {
        return static_cast<unsigned>(llvm::find(ids, id) - ids.begin());
      };
      if (graph.functions().size() != n)
        fail("the graph holds " + std::to_string(graph.functions().size()) + " functions");
      std::vector<unsigned> membership(n, 0);
      for (auto component : graph.sccCount().ids())
        for (FunctionId member : graph.members(component)) {
          ++membership[indexOf(member)];
          if (graph.sccOf(member) != component)
            fail(nameOf(indexOf(member)) + " is a member of another component than its own");
        }
      for (unsigned f = 0; f < n; ++f) {
        FunctionId id = ids[f];
        if (membership[f] != 1)
          fail(nameOf(f) + " is a member " + std::to_string(membership[f]) + " times");
        Row row;
        for (const idr::solver::Call &call : graph.callees(id))
          row.emplace_back(indexOf(call.callee), call.kind, call.sites);
        std::ranges::sort(row);
        if (row != model.rows[f])
          fail(nameOf(f) + "'s row is not its calls");
        std::vector<unsigned> callers, expected;
        for (FunctionId caller : graph.callers(id))
          callers.push_back(indexOf(caller));
        std::uint32_t sites = 0;
        for (unsigned g = 0; g < n; ++g)
          for (const auto &entry : model.rows[g])
            if (std::get<0>(entry) == f) {
              sites += std::get<2>(entry);
              if (expected.empty() || expected.back() != g)
                expected.push_back(g);
            }
        std::ranges::sort(callers);
        if (callers != expected)
          fail(nameOf(f) + "'s callers are not the functions that call it");
        if (graph.callSites(id) != sites)
          fail(nameOf(f) + " has " + std::to_string(graph.callSites(id)) + " call sites");
        bool calledBySelf = llvm::any_of(model.rows[f], [&](const auto &entry) { return std::get<0>(entry) == f; });
        if (graph.callsItself(id) != calledBySelf)
          fail(nameOf(f) + "'s call of itself");
        if (graph.onCycle(id) != model.reaches[f][f])
          fail(nameOf(f) + " on a cycle");
        for (unsigned g = 0; g < n; ++g) {
          bool together = f == g || (model.reaches[f][g] && model.reaches[g][f]);
          if ((graph.sccOf(id) == graph.sccOf(ids[g])) != together)
            fail(nameOf(f) + " and " + nameOf(g) + " together");
          bool calls = llvm::any_of(model.rows[f], [&](const auto &entry) { return std::get<0>(entry) == g; });
          if (calls && !together && !(graph.sccOf(ids[g]) < graph.sccOf(id)))
            fail(nameOf(g) + "'s component is not before " + nameOf(f) + "'s");
        }
      }
    }
    if (why.empty())
      continue;
    ++failures;
    if (report == Report::Each)
      ADD_FAILURE() << "seed " << seed << ":" << why << "\nin the program:" << describe(program);
  }
  return failures;
}

TEST(ProgramGraph, EveryProgramAgainstItsCalls) {
  EXPECT_EQ(judge<truth>(10, Report::Each), 0u);
}

// A row keyed by its callee alone: a call in tail position and one that
// is not are taken for one kind of call.
Model kindsMerged(const Program &program) {
  Program merged = program;
  for (std::vector<Call> &calls : merged)
    for (Call &call : calls)
      call.kind = TailKind::nontail;
  return truth(merged);
}

// A row counting a callee and kind once, however many calls have it.
Model sitesOnce(const Program &program) {
  Model model = truth(program);
  for (Row &row : model.rows)
    for (auto &entry : row)
      std::get<2>(entry) = 1;
  return model;
}

// A call of itself taken for no cycle.
Model selfCallsAcyclic(const Program &program) {
  Program others = program;
  for (unsigned f = 0; f < others.size(); ++f)
    std::erase_if(others[f], [&](Call call) { return call.callee == f; });
  Model model = truth(program);
  model.reaches = truth(others).reaches;
  return model;
}

// The judgement can fail: each model with a planted fault disagrees with
// the graph on some program.
TEST(ProgramGraph, EachMutantModelIsCaught) {
  EXPECT_GT(judge<kindsMerged>(1, Report::None), 0u);
  EXPECT_GT(judge<sitesOnce>(1, Report::None), 0u);
  EXPECT_GT(judge<selfCallsAcyclic>(1, Report::None), 0u);
}

} // namespace
