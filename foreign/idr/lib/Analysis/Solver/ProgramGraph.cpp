// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The program graph: built on upstream's call graph, frozen, thawed by the
// one restructuring pass that edits calls, and frozen again.
#include "idr/Analysis/Solver/ProgramGraph.h"

#include "idr/Analysis/Solver/Components.h"

#include "mlir/Analysis/CallGraph.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <optional>
#include <tuple>
#include <utility>

MLIR_DEFINE_EXPLICIT_TYPE_ID(idr::solver::ProgramGraph)

using namespace mlir;

namespace idr::solver {

namespace {

// A row in one order, each (callee, kind) once with its calls summed: what
// every row of a frozen graph is, whoever wrote it, so equal rows are equal
// bytes and nothing downstream depends on the order calls were met.
void normalize(footprint::Vector<Call> &row) {
  llvm::sort(row, [](const Call &a, const Call &b) {
    return std::tuple(a.callee.index(), a.kind) < std::tuple(b.callee.index(), b.kind);
  });
  footprint::Vector<Call> merged;
  for (const Call &call : row) {
    if (!merged.empty() && merged.back().callee == call.callee && merged.back().kind == call.kind)
      merged.back().sites += call.sites;
    else
      merged.push_back(call);
  }
  row = std::move(merged);
}

// `fn`'s calls as a row, each callee resolved by `resolve`, which gives none
// for a callee that is no function yet: the one reading of a body's calls
// into a row.
template <class Resolve>
footprint::Vector<Call> rowFrom(FuncOp fn, const Resolve &resolve) {
  footprint::Vector<Call> row;
  fn.getBody().walk([&](CallOp call) {
    if (std::optional<FunctionId> callee = resolve(call.getCalleeAttr()))
      row.push_back({*callee, call.getTailKind(), 1});
  });
  normalize(row);
  return row;
}

} // namespace

ProgramGraph::ProgramGraph(Operation *program, AnalysisManager &am) {
  const CallGraph &graph = am.getAnalysis<CallGraph>();
  std::uint32_t ids = graph.getNumIndices();
  count = detail::GraphIds::functions(ids);
  ops = IndexVector<FunctionId, FuncOp>(count, FuncOp());
  // Every callable of a first-order program is an idr.func, nested in the
  // program; upstream's external nodes have no region and stay gaps.
  for (CallGraphNode *node : graph) {
    if (node->isExternal())
      continue;
    auto fn = cast<FuncOp>(node->getCallableRegion()->getParentOp());
    FunctionId f = detail::GraphIds::function(node->getIndex());
    ops[f] = fn;
    byName.try_emplace(fn.getSymNameAttr(), f);
  }
  for (FunctionId f : count.ids())
    if (ops[f])
      live.push_back(f.index());

  // Each function's calls, in parallel, each into its own slot; the slots
  // are read back in id order, so the rows do not depend on the schedule.
  footprint::Vector<footprint::Vector<Call>> perFunction(ids);
  parallelFor(program->getContext(), 0, live.size(), [&](std::size_t at) {
    std::uint32_t raw = live[at];
    perFunction[raw] = rowFrom(ops[detail::GraphIds::function(raw)],
                               [&](FlatSymbolRefAttr callee) -> std::optional<FunctionId> {
                                 return id(callee);
                               });
  });
  lay(std::move(perFunction));

  // Upstream's components, bottom-up, each a run of the permutation; an
  // external node belongs to no component of the program.
  scc.assign(ids, 0);
  for (ArrayRef<CallGraphNode *> component : graph.getSCCs()) {
    auto at = static_cast<std::uint32_t>(sccStart.size() - 1);
    std::size_t before = order.size();
    for (CallGraphNode *node : component) {
      if (node->isExternal())
        continue;
      order.push_back(node->getIndex());
      scc[node->getIndex()] = at;
    }
    if (order.size() != before)
      sccStart.push_back(static_cast<std::uint32_t>(order.size()));
  }
}

FunctionId ProgramGraph::id(FlatSymbolRefAttr callee) const {
  return byName.find(callee.getAttr())->second;
}

FunctionId ProgramGraph::id(FuncOp fn) const { return byName.find(fn.getSymNameAttr())->second; }

void ProgramGraph::lay(footprint::Vector<footprint::Vector<Call>> perFunction) {
  std::uint32_t ids = count.value();
  rowStart.assign(ids + 1, 0);
  rows.clear();
  selfCalls = BitSet<FunctionId>(count);
  sites.assign(ids, 0);
  footprint::Vector<std::pair<std::uint32_t, std::uint32_t>> callerEdges;
  for (std::uint32_t raw = 0; raw < ids; ++raw) {
    footprint::Vector<Call> &row = perFunction[raw];
    normalize(row);
    std::uint32_t lastCallee = ids;
    for (const Call &call : row) {
      rows.push_back(call);
      sites[call.callee.index()] += call.sites;
      if (call.callee.index() == raw)
        (void)selfCalls.raise(call.callee);
      // A callee met under two kinds is one caller.
      if (call.callee.index() != lastCallee)
        callerEdges.emplace_back(call.callee.index(), raw);
      lastCallee = call.callee.index();
    }
    rowStart[raw + 1] = static_cast<std::uint32_t>(rows.size());
  }
  ::idr::detail::layOut(ids, callerEdges, ::idr::detail::Root::Absent, callerStart, callerRows);
}

// The components of the rows: the same Tarjan upstream's graph runs, over
// the frozen rows instead of the IR.
void ProgramGraph::partition() {
  std::uint32_t ids = count.value();
  CsrBuilder<FunctionTag> calls(count);
  for (std::uint32_t raw = 0; raw < ids; ++raw)
    for (const Call &call : callees(detail::GraphIds::function(raw)))
      calls.edge(detail::GraphIds::function(raw), call.callee);
  Csr<FunctionTag> csr = std::move(calls).finish();
  Partition<FunctionTag> parts = components(csr);
  order.clear();
  sccStart.assign(1, 0);
  scc.assign(ids, 0);
  for (auto c : parts.size().ids()) {
    auto at = static_cast<std::uint32_t>(sccStart.size() - 1);
    std::size_t before = order.size();
    for (FunctionId f : parts.members(c)) {
      if (!ops[f])
        continue;
      order.push_back(f.index());
      scc[f.index()] = at;
    }
    if (order.size() != before)
      sccStart.push_back(static_cast<std::uint32_t>(order.size()));
  }
}

Editor ProgramGraph::thaw() & {
  Editor editor(*this);
  std::uint32_t ids = count.value();
  editor.rows.resize(ids);
  editor.ops.resize(ids);
  for (std::uint32_t raw = 0; raw < ids; ++raw) {
    FunctionId f = detail::GraphIds::function(raw);
    editor.ops[raw] = ops[f];
    llvm::append_range(editor.rows[raw], callees(f));
  }
  editor.byName = std::move(byName);
  // The graph holds no rows while the editor does.
  *this = ProgramGraph();
  return editor;
}

FunctionId Editor::insert(FuncOp fn) {
  FunctionId f = detail::GraphIds::function(static_cast<std::uint32_t>(rows.size()));
  rows.emplace_back();
  ops.push_back(fn);
  byName.try_emplace(fn.getSymNameAttr(), f);
  return f;
}

void Editor::erase(FunctionId f) {
  byName.erase(ops[f.index()].getSymNameAttr());
  ops[f.index()] = FuncOp();
  rows[f.index()].clear();
  for (footprint::Vector<Call> &row : rows)
    llvm::erase_if(row, [&](const Call &call) { return call.callee == f; });
}

void Editor::setCallees(FunctionId f, ArrayRef<Call> row) {
  rows[f.index()].assign(row.begin(), row.end());
}

void Editor::moveInto(FunctionId f, FunctionId caller) {
  footprint::Vector<Call> &into = rows[caller.index()];
  llvm::erase_if(into, [&](const Call &call) { return call.callee == f; });
  llvm::append_range(into, rows[f.index()]);
}

FunctionId Editor::id(FlatSymbolRefAttr callee) const {
  return byName.find(callee.getAttr())->second;
}

std::optional<FunctionId> Editor::find(FlatSymbolRefAttr callee) const {
  auto it = byName.find(callee.getAttr());
  if (it == byName.end())
    return std::nullopt;
  return it->second;
}

footprint::Vector<Call> rowOf(FuncOp fn, const Editor &editor) {
  return rowFrom(fn, [&](FlatSymbolRefAttr callee) { return editor.find(callee); });
}

void Editor::freeze() && {
  ProgramGraph &graph = *home;
  auto ids = static_cast<std::uint32_t>(rows.size());
  graph.count = detail::GraphIds::functions(ids);
  graph.ops = IndexVector<FunctionId, FuncOp>(graph.count, FuncOp());
  graph.live.clear();
  for (std::uint32_t raw = 0; raw < ids; ++raw) {
    FunctionId f = detail::GraphIds::function(raw);
    graph.ops[f] = ops[raw];
    if (ops[raw])
      graph.live.push_back(raw);
  }
  graph.byName = std::move(byName);
  graph.lay(std::move(rows));
  graph.partition();
}

} // namespace idr::solver
