// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The in-place rule over the whole program (Rule.h): what each callee
// keeps of its parameters, each function's summaries, and the obligation
// closure with its refusals. Each is total and carries no budget: the
// markings rise once per node, and the summaries rise in a finite lattice.
#include "idr/Transforms/InPlace/Rule.h"

#include "idr/Analysis/Ownership/Facts.h"
#include "idr/Analysis/Ownership/Local.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/Mark.h"

#include "llvm/ADT/STLExtras.h"

#include <array>
#include <utility>
#include <vector>

using namespace mlir;

namespace idr::inplace {

namespace {

constexpr std::array<Asks, 2> strengths{Asks::Self, Asks::Deep};

// The nodes of one of this unit's markings, numbered by that marking.
struct Nodes;
struct NodeTag {
  using Minter = Nodes;
};
using Node = Id<NodeTag>;
struct Nodes {
  static Node at(std::uint32_t n) { return Node(n); }
  static Count<Node> count(std::uint32_t n) { return Count<Node>(n); }
};

// The marking of `count` nodes from `seeds` along `edges`, each edge "the
// first marked marks the second".
BitSet<Node> markAll(std::uint32_t count,
                     llvm::ArrayRef<std::pair<std::uint32_t, std::uint32_t>> edges,
                     llvm::ArrayRef<std::uint32_t> seeds) {
  CsrBuilder<NodeTag> builder(Nodes::count(count));
  for (auto [from, to] : edges)
    builder.edge(Nodes::at(from), Nodes::at(to));
  footprint::Vector<Node> starts;
  for (std::uint32_t seed : seeds)
    starts.push_back(Nodes::at(seed));
  Csr<NodeTag> graph = std::move(builder).finish();
  return mark<Forward>(graph, std::span<const Node>(starts));
}

// What the boundary grades a parameter of `type` with, owed by every caller
// whatever the body does with it: what its family's promise asks, its own
// cells unshared, which reaches the storage of a buffer one of them holds
// and never its elements. The held buffer says only when that is owed,
// not how much: a parameter of quantity 1 whose family's own cells hold a
// buffer carries the promise by construction, since bufferization writes
// the buffer in place; any other is graded nothing here, its promise
// binding where a cell is rebuilt.
std::optional<Asks> boundaryAsks(Type type) {
  DataType data = ownership::familyOf(type);
  if (!data || usesOf(type) != Uses::Once ||
      data.getGroup().ownBuffers(data.getMember()) != Buffers::HoldsBuffer)
    return std::nullopt;
  return ownership::promisedAsks(data);
}

// The requirement's targets as a summary: impossible where one reached a
// cause, else each parameter at the strongest strength asked of it.
Need needOf(llvm::ArrayRef<Target> targets) {
  Need need(std::in_place);
  for (const Target &target : targets) {
    if (target.kind == Target::Kind::Cause)
      return std::nullopt;
    if (!need->empty() && need->back().first == target.index)
      need->back().second = std::max(need->back().second, target.asks);
    else
      need->push_back({target.index, target.asks});
  }
  return need;
}

} // namespace

Keeps keepsOf(const solver::ProgramGraph &graph) {
  Keeps keeps(graph);
  IndexVector<FunctionId, std::uint32_t> base = graph.table<std::uint32_t>();
  std::uint32_t nodes = 0;
  for (FunctionId fn : graph.functions()) {
    base[fn] = nodes;
    nodes += graph.op(fn).getNumArguments();
  }
  footprint::Vector<std::pair<std::uint32_t, std::uint32_t>> edges;
  footprint::Vector<std::uint32_t> seeds;
  for (FunctionId fn : graph.functions()) {
    FuncOp op = graph.op(fn);
    for (BlockArgument param : op.getBody().front().getArguments()) {
      if (!holdsReferences(param.getType()))
        continue;
      std::uint32_t here = base[fn] + param.getArgNumber();
      // Each use of the parameter, and of what a use hands it on as, on an
      // explicit stack: a callee keeps what it keeps, so lent on, the
      // parameter is kept where the callee's is; any passage that keeps it
      // outlives the call.
      SmallVector<OpOperand *> work;
      auto push = [&](Value of) {
        for (OpOperand &use : of.getUses())
          work.push_back(&use);
      };
      push(param);
      while (!work.empty()) {
        OpOperand *use = work.pop_back_val();
        ownership::Passage passage = ownership::passageOf(
            *use, [&](Value on, ownership::Runs) { push(on); },
            [&](const FlowSource::Parameter &lent) {
              edges.emplace_back(base[graph.id(lent.function)] + lent.index, here);
            });
        if (passage == ownership::Passage::Keeps) {
          seeds.push_back(here);
          break;
        }
      }
    }
  }
  BitSet<Node> kept = markAll(nodes, edges, seeds);
  // Each function's bits, a parameter each, counted as MLIR counts them.
  for (FunctionId fn : graph.functions()) {
    unsigned params = graph.op(fn).getNumArguments();
    keeps.kept[fn].resize(params);
    for (unsigned param = 0; param != params; ++param)
      if (kept.test(Nodes::at(base[fn] + param)))
        keeps.kept[fn].set(param);
  }
  return keeps;
}

Summaries summariesOf(const solver::ProgramGraph &graph, const Keeps &keeps, solver::Work &work) {
  Summaries summaries(graph);
  for (FunctionId fn : graph.functions())
    summaries.reserve(fn, graph.op(fn).getNumResults());
  std::uint64_t transfers = 0;
  for (solver::SccId component : graph.sccCount().ids())
    for (bool grew = true; grew;) {
      grew = false;
      for (FunctionId fn : graph.members(component)) {
        FuncOp op = graph.op(fn);
        auto ret = dyn_cast<ReturnOp>(op.getBody().front().getTerminator());
        // A function that never returns gives back nothing to ask of.
        if (!ret)
          continue;
        ++transfers;
        Chains chains(op, graph, summaries, keeps);
        for (auto [result, operand] : llvm::enumerate(ret->getOpOperands())) {
          if (!holdsReferences(operand.get().getType()))
            continue;
          for (Asks asks : strengths) {
            Need need = needOf(chains.targets(operand.get(), asks));
            Need &known = summaries.of(fn, static_cast<unsigned>(result), asks);
            if (need != known) {
              known = std::move(need);
              grew = true;
            }
          }
        }
      }
    }
  work.add(transfers);
  return summaries;
}

Verdict decide(const solver::ProgramGraph &graph, const Summaries &summaries,
               const Keeps &keeps) {
  Verdict verdict(graph);
  // A node per (parameter, strength), each function's after the one before;
  // a node per refusal after them, numbered as they are found.
  IndexVector<FunctionId, std::uint32_t> base = graph.table<std::uint32_t>();
  std::uint32_t parameters = 0;
  for (FunctionId fn : graph.functions()) {
    base[fn] = parameters;
    parameters += graph.op(fn).getNumArguments() * 2;
  }
  auto node = [&](FunctionId fn, std::uint32_t param, Asks asks) {
    return base[fn] + param * 2 + static_cast<std::uint32_t>(asks);
  };
  footprint::Vector<Refusal> found;
  auto refusal = [&](Refusal each) {
    found.push_back(each);
    return parameters + static_cast<std::uint32_t>(found.size() - 1);
  };
  footprint::Vector<std::pair<std::uint32_t, std::uint32_t>> edges;
  footprint::Vector<std::uint32_t> seeds;
  for (FunctionId fn : graph.functions()) {
    FuncOp op = graph.op(fn);
    Chains chains(op, graph, summaries, keeps);
    // Where a target lands: a parameter's node, or a refusal of the start.
    auto land = [&](const Target &target, Operation *at, std::optional<FuncOp> callee,
                    DataType family) {
      if (target.kind == Target::Kind::Parameter)
        return node(fn, target.index, target.asks);
      return refusal({op, at, callee, family, chains.causes()[target.index]});
    };
    for (const RebuildSite &site : rebuildSites(op, chains.numbering())) {
      verdict.sites[fn].push_back(site);
      DataType family = ownership::familyOf(site.taken.getType());
      for (const Target &target : chains.targets(site.taken, site.asks))
        seeds.push_back(land(target, site.match, std::nullopt, family));
    }
    for (BlockArgument param : op.getBody().front().getArguments())
      if (std::optional<Asks> owed = boundaryAsks(param.getType()))
        seeds.push_back(node(fn, param.getArgNumber(), *owed));
    ownership::forEachCall(op, [&](FunctionCallOpInterface call) {
      FunctionId callee = graph.id(call.getCalleeAttr());
      FuncOp calleeOp = graph.op(callee);
      for (auto [param, arg] : llvm::enumerate(call->getOpOperands())) {
        if (!holdsReferences(arg.get().getType()))
          continue;
        DataType family = ownership::familyOf(calleeOp.getArgumentTypes()[param]);
        for (Asks asks : strengths) {
          std::uint32_t owed = node(callee, static_cast<std::uint32_t>(param), asks);
          for (const Target &target : chains.targets(arg.get(), asks))
            edges.emplace_back(owed, land(target, call, calleeOp, family));
        }
      }
    });
  }
  BitSet<Node> owed =
      markAll(parameters + static_cast<std::uint32_t>(found.size()), edges, seeds);
  for (FunctionId fn : graph.functions()) {
    unsigned params = graph.op(fn).getNumArguments();
    verdict.obligations[fn].assign(params, std::nullopt);
    for (unsigned param = 0; param != params; ++param)
      for (Asks asks : strengths)
        if (owed.test(Nodes::at(node(fn, param, asks))))
          verdict.obligations[fn][param] = asks;
  }
  // Once per cause: the first start the marking reached it from.
  for (auto [index, each] : llvm::enumerate(found))
    if (owed.test(Nodes::at(parameters + static_cast<std::uint32_t>(index))) &&
        llvm::none_of(verdict.refusals,
                      [&](const Refusal &earlier) { return earlier.cause.at == each.cause.at; }))
      verdict.refusals.push_back(each);
  return verdict;
}

} // namespace idr::inplace
