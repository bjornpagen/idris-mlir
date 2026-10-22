// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Exclusivity's solve by context, over the bodies ExclusivityGraph.cpp read.
//
// A context is a function with the followed parameters it takes exclusive.
// Every function's general context, which takes none, runs: it is what the
// original symbol keeps, safe for any caller. A call in a running context
// goes to the context of its callee keyed by the followed parameters it
// passes exclusive values at, which then runs too. With every call's
// target fixed, which contexts run is a reachability over contexts, and
// which values are shared one marking of the product of the running
// contexts' bodies: no gate waits on another mark. A call's key is then
// what the marking left exclusive of what it passed before; keys only lose
// parameters (a key starts at every followed parameter and is narrowed by
// the shared arguments of a solve with targets fixed), so the rounds of
// marking end, with no count, when no key moved. Each round marks afresh,
// so a context a call left keeps nothing of it.
//
// The state is a bit per followed value per running context, a bit per
// memo field, and a key per call per running context: sized by the
// program and the contexts its calls reach, which are finite.
#include "idr/Analysis/Ownership/ExclusivityDetail.h"

#include "idr/Analysis/Solver/Graph.h"
#include "idr/Analysis/Solver/Mark.h"

#include "llvm/ADT/STLExtras.h"

#include <vector>

namespace idr::detail::exclusivity {

namespace {

using Key = llvm::SmallBitVector;
using ContextId = std::uint32_t;

// A followed value of a running context, or a memo field: the nodes of one
// round's marking, numbered by that round.
class Solve;
struct NodeTag {
  using Minter = Solve;
};
using Node = Id<NodeTag>;

struct Context {
  FunctionId fn;
  Key key;
  // The key each call of the body passes, in the walk's order of calls.
  std::vector<Key> calls;
};

class Solve {
public:
  Solve(const IndexVector<FunctionId, Body> &bodies,
        const IndexVector<FunctionId, llvm::SmallBitVector> &copied,
        const Anchors &anchors, const solver::ProgramGraph &graph)
      : bodies(bodies), copied(copied), anchors(anchors), graph(graph),
        contextsOf(graph.table<llvm::SmallVector<ContextId, 1>>()) {}

  Solution run() {
    for (FunctionId fn : graph.functions())
      (void)contextFor(fn, Key(static_cast<unsigned>(bodies[fn].params.size())));
    for (;;) {
      ++rounds;
      reachRunning();
      BitSet<Node> shared = mark();
      if (!narrowKeys(shared))
        return answer(shared);
    }
  }

private:
  // The context of `fn` keyed by `key`, made with every call at its widest
  // key when it is new.
  ContextId contextFor(FunctionId fn, const Key &key) {
    for (ContextId id : contextsOf[fn])
      if (contexts[id].key == key)
        return id;
    ContextId id = static_cast<ContextId>(contexts.size());
    Context made{fn, key, {}};
    for (const Call &call : bodies[fn].calls)
      made.calls.push_back(keyOfArgs(call));
    contexts.push_back(std::move(made));
    contextsOf[fn].push_back(id);
    return id;
  }

  // The positions where `call` passes a followed argument: the key a call
  // passes before a solve has shared any argument of it.
  static Key keyOfArgs(const Call &call) {
    Key key(static_cast<unsigned>(call.args.size()));
    for (auto [index, local] : llvm::enumerate(call.args))
      if (local != noLocal)
        key.set(static_cast<unsigned>(index));
    return key;
  }

  ContextId targetOf(ContextId from, std::size_t call) {
    const Call &site = bodies[contexts[from].fn].calls[call];
    // Copied first: making a context may move the one it is read from.
    Key key = contexts[from].calls[call];
    return contextFor(site.callee, key);
  }

  // The contexts that run with every call's target as it stands: every
  // general context, and every context a call of a running one goes to.
  // Each one's nodes start at its base.
  void reachRunning() {
    running.clear();
    base.clear();
    llvm::BitVector seen;
    std::vector<ContextId> work;
    auto reach = [&](ContextId id) {
      if (seen.size() <= id)
        seen.resize(id + 1);
      if (seen.test(id))
        return;
      seen.set(id);
      work.push_back(id);
    };
    for (FunctionId fn : graph.functions())
      reach(contextsOf[fn].front());
    while (!work.empty()) {
      ContextId id = work.back();
      work.pop_back();
      running.push_back(id);
      for (std::size_t call = 0, e = contexts[id].calls.size(); call != e; ++call)
        reach(targetOf(id, call));
    }
    llvm::sort(running);
    base.assign(contexts.size(), 0);
    nodes = 0;
    for (ContextId id : running) {
      base[id] = nodes;
      nodes += bodies[contexts[id].fn].values;
    }
    anchorBase = nodes;
    nodes += anchors.size();
  }

  // The values each running context shares, with every call's target
  // fixed, and the memo fields after them.
  BitSet<Node> mark() {
    CsrBuilder<NodeTag> edges(Count<Node>(nodes));
    std::vector<Node> seeds;
    auto edge = [&](std::uint32_t from, std::uint32_t to) { edges.edge(Node(from), Node(to)); };
    auto seed = [&](std::uint32_t at) { seeds.push_back(Node(at)); };
    for (Anchor anchor : anchors.shared())
      seed(anchorBase + anchor);
    for (ContextId id : running) {
      const Context &context = contexts[id];
      const Body &body = bodies[context.fn];
      std::uint32_t at = base[id];
      for (const Edge &each : body.edges)
        edge(at + each.from, at + each.to);
      for (Local local : body.seeds)
        seed(at + local);
      // A followed parameter the context does not take exclusive is shared.
      for (auto [index, local] : llvm::enumerate(body.params))
        if (local != noLocal && !context.key.test(static_cast<unsigned>(index)))
          seed(at + local);
      for (auto [index, call] : llvm::enumerate(body.calls)) {
        ContextId target = targetOf(id, index);
        const Body &callee = bodies[call.callee];
        for (auto [result, local] : llvm::enumerate(call.results)) {
          if (local == noLocal)
            continue;
          Local returned = callee.returns ? callee.results[result] : noLocal;
          if (returned != noLocal)
            edge(base[target] + returned, at + local);
          else if (!callee.returns || !callee.exclusiveResults.test(result))
            seed(at + local);
        }
        // A view passed to a parameter the callee takes a reference of
        // through a view: its owner here is shared.
        for (const auto &[param, root] : call.views)
          if (root.kind == ViewRoot::Kind::Value && copied[call.callee].test(param))
            seed(at + root.index);
      }
      for (const auto &[local, anchor] : body.intoAnchors)
        edge(at + local, anchorBase + anchor);
      for (const auto &[anchor, local] : body.outOfAnchors)
        edge(anchorBase + anchor, at + local);
    }
    Csr<NodeTag> graphOfValues = std::move(edges).finish();
    return idr::mark(graphOfValues, std::span<const Node>(seeds), Forward{});
  }

  // Narrows each running call's key to the arguments the marking left
  // exclusive; whether any key moved.
  bool narrowKeys(const BitSet<Node> &shared) {
    bool moved = false;
    for (ContextId id : running) {
      Context &context = contexts[id];
      const Body &body = bodies[context.fn];
      for (auto [index, call] : llvm::enumerate(body.calls)) {
        Key &key = context.calls[index];
        Key narrowed = key;
        for (int param = narrowed.find_first(); param != -1; param = narrowed.find_next(param))
          if (shared.test(Node(base[id] + call.args[static_cast<unsigned>(param)])))
            narrowed.reset(static_cast<unsigned>(param));
        if (narrowed != key) {
          key = std::move(narrowed);
          moved = true;
        }
      }
    }
    return moved;
  }

  // What one running context proved: its exclusive values, its exclusive
  // results, and the context each call goes to.
  struct Proof {
    llvm::BitVector exclusive;
    llvm::SmallBitVector results;
    llvm::SmallVector<ContextId> targets;
    bool operator==(const Proof &) const = default;
  };

  Proof proofOf(ContextId id, const BitSet<Node> &shared) {
    const Body &body = bodies[contexts[id].fn];
    Proof proof;
    proof.exclusive.resize(body.values);
    for (std::uint32_t local = 0; local != body.values; ++local)
      if (!shared.test(Node(base[id] + local)))
        proof.exclusive.set(local);
    proof.results.resize(static_cast<unsigned>(body.exclusiveResults.size()));
    if (body.returns)
      for (auto [index, local] : llvm::enumerate(body.results))
        if (local == noLocal ? body.exclusiveResults.test(index) : proof.exclusive.test(local))
          proof.results.set(static_cast<unsigned>(index));
    for (std::size_t call = 0, e = body.calls.size(); call != e; ++call)
      proof.targets.push_back(targetOf(id, call));
    return proof;
  }

  // What a context proves beyond its own parameters, by which it is
  // compared with the general one: a copy buys something only where a value
  // of its body is exclusive that the general context's is not.
  static bool sameBeyondParameters(const Proof &a, const Proof &b, const Body &body) {
    llvm::BitVector difference = a.exclusive;
    difference ^= b.exclusive;
    for (Local param : body.params)
      if (param != noLocal)
        difference.reset(param);
    return difference.none() && a.results == b.results && a.targets == b.targets;
  }

  // The versions of each function: its general context first; a running
  // context that proves nothing beyond its parameters that the general one
  // does not is that version (its calls go to the original, their
  // exclusive arguments shared into it); contexts whose proofs are equal
  // are one copy. Then each version's calls go to the versions of their
  // target contexts.
  Solution answer(const BitSet<Node> &shared) {
    Solution out{graph.table<llvm::SmallVector<Exclusivity::Version, 1>>()};
    out.rounds = rounds;
    out.contexts = static_cast<unsigned>(running.size());
    std::vector<std::uint32_t> versionOf(contexts.size(), 0);
    std::vector<Proof> proofs(contexts.size());
    llvm::BitVector isRunning(static_cast<unsigned>(contexts.size()));
    for (ContextId id : running) {
      isRunning.set(id);
      proofs[id] = proofOf(id, shared);
    }
    // The context each version is made from, by function.
    IndexVector<FunctionId, llvm::SmallVector<ContextId, 1>> madeFrom =
        graph.table<llvm::SmallVector<ContextId, 1>>();
    for (FunctionId fn : graph.functions()) {
      ContextId general = contextsOf[fn].front();
      madeFrom[fn].push_back(general);
      for (ContextId id : llvm::drop_begin(contextsOf[fn])) {
        if (!isRunning.test(id))
          continue;
        if (sameBeyondParameters(proofs[id], proofs[general], bodies[fn]))
          continue;
        auto same = llvm::find_if(llvm::drop_begin(madeFrom[fn]),
                                  [&](ContextId other) { return proofs[other] == proofs[id]; });
        if (same != madeFrom[fn].end()) {
          versionOf[id] = versionOf[*same];
          continue;
        }
        versionOf[id] = static_cast<std::uint32_t>(madeFrom[fn].size());
        madeFrom[fn].push_back(id);
      }
      out.copies += static_cast<unsigned>(madeFrom[fn].size()) - 1;
    }
    for (FunctionId fn : graph.functions())
      for (ContextId id : madeFrom[fn]) {
        Exclusivity::Version version{contexts[id].key, proofs[id].exclusive, proofs[id].results,
                                     {}};
        for (ContextId target : proofs[id].targets)
          version.callTargets.push_back(versionOf[target]);
        out.versions[fn].push_back(std::move(version));
      }
    return out;
  }

  const IndexVector<FunctionId, Body> &bodies;
  const IndexVector<FunctionId, llvm::SmallBitVector> &copied;
  const Anchors &anchors;
  const solver::ProgramGraph &graph;
  std::vector<Context> contexts;
  IndexVector<FunctionId, llvm::SmallVector<ContextId, 1>> contextsOf;
  std::vector<ContextId> running;
  std::vector<std::uint32_t> base;
  std::uint32_t nodes = 0;
  std::uint32_t anchorBase = 0;
  unsigned rounds = 0;
};

} // namespace

Solution solve(const IndexVector<FunctionId, Body> &bodies,
               const IndexVector<FunctionId, llvm::SmallBitVector> &copied,
               const Anchors &anchors, const solver::ProgramGraph &graph) {
  return Solve(bodies, copied, anchors, graph).run();
}

} // namespace idr::detail::exclusivity
