// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The versions a verdict makes of each function (Rule.h, versionsOf): what
// each value is graded with, what each parameter is owed and each result
// gives back, and which version of its callee each call goes to, all by
// the positions of the one walk of each original body, read before
// anything changes it. Every value a requirement reaches is graded with
// its claim; a call whose result must be given back with a claim goes to a
// version of its callee that gives it: the original, where the callee's own
// obligations already ask all the summary needs, else a grade copy keyed by
// the results it gives and the parameters it is owed. Nothing here changes
// the program (Writer.cpp writes it).
#include "idr/Transforms/InPlace/Rule.h"

#include "idr/Analysis/Ownership/Walks.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"

#include <optional>
#include <utility>

using namespace mlir;

namespace idr::inplace {

namespace {

// The stronger of two claims asked of one value.
void raise(std::optional<Asks> &held, Asks asks) {
  if (!held || *held < asks)
    held = asks;
}

class Solve {
public:
  Solve(const solver::ProgramGraph &graph, const Summaries &summaries, const Keeps &keeps,
        const Verdict &verdict)
      : graph(graph), summaries(summaries), keeps(keeps), verdict(verdict), out(graph),
        bodies(graph.table<Version>()) {}

  Versions run() && {
    for (FunctionId fn : graph.functions())
      readBody(fn);
    for (FunctionId fn : graph.functions())
      if (!out.of[fn].empty())
        resolve(fn, 0);
    while (!pending.empty()) {
      auto [fn, version] = pending.pop_back_val();
      traceReturns(fn, version);
    }
    // Each rebuild site by its places in the walk of its original body.
    for (FunctionId fn : graph.functions())
      for (const RebuildSite &site : verdict.sites[fn])
        out.sites[fn].push_back(site.at);
    return std::move(out);
  }

private:
  // A version of `fn` that asks nothing: a slot per value and per call of
  // its original body, by place.
  Version blank(FunctionId fn) {
    FuncOp op = graph.op(fn);
    Walk walk(op);
    Version version;
    version.results.assign(op.getNumResults(), std::nullopt);
    version.params.assign(verdict.obligations[fn].begin(), verdict.obligations[fn].end());
    version.grades.assign(walk.values.size(), std::nullopt);
    version.demands.assign(walk.calls.size(), {});
    version.targets.assign(walk.calls.size(), 0);
    return version;
  }

  // What a body's own starts reach: each rebuild site's cell, and each
  // argument its callee is owed. Every version of the body holds it. A
  // body none of whose values the verdict reaches, and which no call asks a
  // version of, has no version: nothing of it changes but the results of
  // the calls it makes.
  void readBody(FunctionId fn) {
    FuncOp op = graph.op(fn);
    Chains chains(op, graph, summaries, keeps);
    Chains::Reached reached;
    for (const RebuildSite &site : verdict.sites[fn])
      chains.trace(site.taken, site.asks, reached);
    ownership::forEachCall(op, [&](CallOp call) {
      FunctionId callee = graph.id(call.getCalleeAttr());
      for (auto [param, arg] : llvm::enumerate(call.getArgOperands()))
        if (std::optional<Asks> owed = verdict.obligations[callee][param])
          chains.trace(arg, *owed, reached);
    });
    if (reached.values.empty() && llvm::none_of(verdict.obligations[fn], [](auto owed) {
          return owed.has_value();
        }))
      return;
    ensure(fn);
    record(bodies[fn], reached);
    out.of[fn].front() = bodies[fn];
  }

  // `fn`'s original version, made where a call first asks one of it.
  void ensure(FunctionId fn) {
    if (!out.of[fn].empty())
      return;
    bodies[fn] = blank(fn);
    out.of[fn].push_back(bodies[fn]);
  }

  void record(Version &version, const Chains::Reached &reached) {
    for (auto [place, asks] : reached.values)
      raise(version.grades[place], asks);
    for (const Chains::Demand &demand : reached.demands) {
      auto &asked = version.demands[demand.place];
      if (asked.empty())
        asked.assign(demand.call->getNumResults(), std::nullopt);
      raise(asked[demand.result], demand.asks);
    }
  }

  // What a version that gives back `results` is owed: its function's
  // obligations, and what the summaries of those results need, which may
  // ask no more than the obligations do.
  enum class Beyond : std::uint8_t { Nothing, More };
  struct Owed {
    llvm::SmallVector<std::optional<Asks>, 4> params;
    Beyond beyond = Beyond::Nothing;
  };
  Owed owedFor(FunctionId fn, llvm::ArrayRef<std::optional<Asks>> results) {
    Owed owed{{verdict.obligations[fn].begin(), verdict.obligations[fn].end()}, Beyond::Nothing};
    for (auto [result, asks] : llvm::enumerate(results)) {
      if (!asks)
        continue;
      // Every requirement the verdict reached was met, so its summary is.
      const Need &need = summaries.of(fn, static_cast<unsigned>(result), *asks);
      for (auto [param, strength] : *need)
        if (!owed.params[param] || *owed.params[param] < strength) {
          raise(owed.params[param], strength);
          owed.beyond = Beyond::More;
        }
    }
    return owed;
  }

  // Each call of a version goes to the version of its callee that gives
  // back what the call asks: the original, merged with what it asks, where
  // the callee's obligations cover what that needs; else a copy keyed by
  // its results.
  void resolve(FunctionId fn, std::uint32_t at) {
    Walk walk(graph.op(fn));
    for (auto [index, call] : llvm::enumerate(walk.calls)) {
      // Copied: making a version may move the one it is read from.
      llvm::SmallVector<std::optional<Asks>, 1> asked = out.of[fn][at].demands[index];
      if (asked.empty())
        continue;
      FunctionId callee = graph.id(call.getCalleeAttr());
      ensure(callee);
      Owed owed = owedFor(callee, asked);
      std::uint32_t target = 0;
      if (owed.beyond == Beyond::Nothing) {
        Version &original = out.of[callee].front();
        bool grew = false;
        for (auto [held, asks] : llvm::zip_equal(original.results, asked))
          if (asks && (!held || *held < *asks)) {
            held = asks;
            grew = true;
          }
        if (grew)
          pending.push_back({callee, 0});
      } else {
        auto same = llvm::find_if(out.of[callee], [&](const Version &other) {
          return llvm::equal(other.results, asked);
        });
        target = static_cast<std::uint32_t>(same - out.of[callee].begin());
        if (same == out.of[callee].end()) {
          Version copy = bodies[callee];
          copy.results.assign(asked.begin(), asked.end());
          copy.params = std::move(owed.params);
          out.of[callee].push_back(std::move(copy));
          pending.push_back({callee, target});
        }
      }
      out.of[fn][at].targets[index] = target;
    }
  }

  // What a version's results reach, given back at their claims.
  void traceReturns(FunctionId fn, std::uint32_t at) {
    FuncOp op = graph.op(fn);
    auto ret = dyn_cast<ReturnOp>(op.getBody().front().getTerminator());
    if (!ret)
      return;
    Chains chains(op, graph, summaries, keeps);
    Chains::Reached reached;
    for (auto [result, asks] : llvm::enumerate(out.of[fn][at].results))
      if (asks)
        chains.trace(ret.getOperand(static_cast<unsigned>(result)), *asks, reached);
    record(out.of[fn][at], reached);
    resolve(fn, at);
  }

  const solver::ProgramGraph &graph;
  const Summaries &summaries;
  const Keeps &keeps;
  const Verdict &verdict;
  Versions out;
  IndexVector<FunctionId, Version> bodies;
  llvm::SmallVector<std::pair<FunctionId, std::uint32_t>> pending;
};

} // namespace

Versions versionsOf(const solver::ProgramGraph &graph, const Summaries &summaries,
                    const Keeps &keeps, const Verdict &verdict) {
  return Solve(graph, summaries, keeps, verdict).run();
}

} // namespace idr::inplace
