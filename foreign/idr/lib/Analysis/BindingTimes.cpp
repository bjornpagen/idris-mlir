// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The binding times of the members of one component: every body read once
// into its call edges, then one flat solve per root. The calls between the
// component's functions are the only edges: after defunctionalization a
// closure's recursion is a direct call in a dispatch, and a force is a
// call of its memo sum's dispatch function, which calls the label.
#include "idr/Analysis/BindingTimes.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Match.h"

#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <optional>
#include <utility>
#include <variant>

using namespace mlir;

namespace idr {

namespace {

// Where an argument comes from in its caller: one of the caller's
// parameters, unchanged, or anything else.
struct FromParameter {
  std::uint32_t param;
};
struct FromAnything {};
using Source = std::variant<FromParameter, FromAnything>;

// The value idr::sourceOf finds `value` the same as, if any.
std::optional<Value> sameAs(Value value) {
  return match(sourceOf(value), [](idr::Same same) -> std::optional<Value> { return same.value; },
               [](idr::Made) -> std::optional<Value> { return std::nullopt; },
               [](const idr::Field &) -> std::optional<Value> { return std::nullopt; });
}

// What `value` is in `fn`: an entry argument is its parameter; what
// idr::sourceOf finds the same value is what that value is; anything else
// is anything. The chain is followed by a loop, never by recursion, each
// step counted in `steps`. It ends where a value is the same as no other:
// each step goes to an operand of the op that defines the value or whose
// region binds it, which dominates it, so no chain comes back to a value
// it passed.
Source sourceIn(Value value, FuncOp fn, std::uint64_t &steps) {
  for (std::optional<Value> at = value; at; at = sameAs(*at)) {
    ++steps;
    if (auto arg = dyn_cast<BlockArgument>(*at); arg && arg.getParentRegion() == &fn.getBody())
      return FromParameter{arg.getArgNumber()};
  }
  return FromAnything{};
}

// A call between members: the members' positions, and where its arguments'
// sources start in the component's one array of sources.
struct Edge {
  std::uint32_t caller, callee, firstSource, sources;
};

// The flat lattice of one (member, parameter) node for one root: not
// reached, the root's parameter `param` unchanged, or anything.
enum class Kind : std::uint8_t { Unreached, Same, Anything };
struct Abstract {
  Kind kind = Kind::Unreached;
  std::uint32_t param = 0;
  friend bool operator==(Abstract, Abstract) = default;
};

Abstract join(Abstract a, Abstract b) {
  if (a.kind == Kind::Unreached)
    return b;
  if (b.kind == Kind::Unreached || a == b)
    return a;
  return {Kind::Anything, 0};
}

// What the component's bodies say, read once: each member's edges out, and
// each member's parameters' slots in the node array.
struct Calls {
  footprint::Vector<Edge> edges;
  footprint::Vector<std::uint32_t> edgeStart;
  footprint::Vector<Source> sources;
  footprint::Vector<std::uint32_t> slot;
};

template <solver::FunctionNames N>
Calls readCalls(const N &names, ArrayRef<solver::Member> component, std::uint64_t &steps) {
  // The members by id, to place a callee: a sorted list, searched, never a
  // map of the program's functions by name.
  footprint::Vector<std::pair<std::uint32_t, std::uint32_t>> byId;
  for (auto [at, member] : llvm::enumerate(component))
    byId.emplace_back(member.id.index(), static_cast<std::uint32_t>(at));
  llvm::sort(byId);
  // A callee outside the component is no edge: the one miss the search
  // has, and an essential one.
  auto positionOf = [&](solver::FunctionId f) -> std::optional<std::uint32_t> {
    auto it = llvm::lower_bound(byId, std::pair(f.index(), 0u));
    if (it == byId.end() || it->first != f.index())
      return std::nullopt;
    return it->second;
  };

  Calls out;
  std::uint32_t slots = 0;
  for (auto [at, member] : llvm::enumerate(component)) {
    // MLIR's op handles read nothing through a const handle, so each
    // member's is copied: a handle, never the op.
    FuncOp fn = member.fn;
    out.slot.push_back(slots);
    slots += fn.getNumArguments();
    out.edgeStart.push_back(static_cast<std::uint32_t>(out.edges.size()));
    fn.getBody().walk([&](CallOp call) {
      std::optional<std::uint32_t> callee = positionOf(names.id(call.getCalleeAttr()));
      if (!callee)
        return;
      auto first = static_cast<std::uint32_t>(out.sources.size());
      for (Value operand : call.getArgs())
        out.sources.push_back(sourceIn(operand, fn, steps));
      out.edges.push_back({static_cast<std::uint32_t>(at), *callee, first,
                           static_cast<std::uint32_t>(out.sources.size()) - first});
    });
  }
  out.slot.push_back(slots);
  out.edgeStart.push_back(static_cast<std::uint32_t>(out.edges.size()));
  return out;
}

// Where a member stands in one root's solve: not reached; reached and on
// the worklist; reached and off it. Only a reached member is ever queued.
enum class Visit : std::uint8_t { Unreached, Queued, Settled };

// The binding times of the root's parameters: the flat solve from the root,
// each member pushed when it is first reached or one of its nodes rises,
// then each call of the root read against its own position. Each edge the
// solve reads and each argument it joins or compares is counted in `steps`.
SmallVector<BindingTime> solveRoot(const Calls &calls, ArrayRef<solver::Member> component,
                                   std::uint32_t root, std::uint64_t &steps) {
  footprint::Vector<Abstract> value(calls.slot.back());
  footprint::Vector<Visit> visit(component.size(), Visit::Unreached);
  footprint::Vector<std::uint32_t> work;
  auto at = [&](std::uint32_t member, std::uint32_t param) -> Abstract & {
    return value[calls.slot[member] + param];
  };
  auto passed = [&](const Edge &edge, std::uint32_t arg) {
    return match(calls.sources[edge.firstSource + arg],
                 [&](FromParameter from) { return at(edge.caller, from.param); },
                 [](FromAnything) { return Abstract{Kind::Anything, 0}; });
  };
  FuncOp rootFn = component[root].fn;
  for (std::uint32_t p = 0; p < rootFn.getNumArguments(); ++p)
    at(root, p) = {Kind::Same, p};
  visit[root] = Visit::Queued;
  work.push_back(root);
  while (!work.empty()) {
    std::uint32_t caller = work.back();
    work.pop_back();
    visit[caller] = Visit::Settled;
    for (std::uint32_t e = calls.edgeStart[caller]; e < calls.edgeStart[caller + 1]; ++e) {
      const Edge &edge = calls.edges[e];
      steps += 1 + edge.sources;
      bool rose = visit[edge.callee] == Visit::Unreached;
      for (std::uint32_t arg = 0; arg < edge.sources; ++arg) {
        Abstract &into = at(edge.callee, arg);
        Abstract joined = join(into, passed(edge, arg));
        if (joined != into) {
          into = joined;
          rose = true;
        }
      }
      if (rose && visit[edge.callee] != Visit::Queued) {
        visit[edge.callee] = Visit::Queued;
        work.push_back(edge.callee);
      }
    }
  }

  SmallVector<BindingTime> times(rootFn.getNumArguments(), BindingTime::Fixed);
  for (const Edge &edge : calls.edges) {
    ++steps;
    if (edge.callee != root || visit[edge.caller] == Visit::Unreached)
      continue;
    steps += edge.sources;
    for (std::uint32_t arg = 0; arg < edge.sources; ++arg)
      if (passed(edge, arg) != Abstract{Kind::Same, arg})
        times[arg] = BindingTime::Varies;
  }
  return times;
}

} // namespace

template <solver::FunctionNames N>
footprint::Vector<SmallVector<BindingTime>>
bindingTimesOf(const N &names, ArrayRef<solver::Member> component, solver::Work &work) {
  std::uint64_t steps = 0;
  Calls calls = readCalls(names, component, steps);
  footprint::Vector<SmallVector<BindingTime>> out;
  out.reserve(component.size());
  for (std::uint32_t root = 0; root < component.size(); ++root)
    out.push_back(solveRoot(calls, component, root, steps));
  work.add(steps);
  return out;
}

template footprint::Vector<SmallVector<BindingTime>>
bindingTimesOf<solver::ProgramGraph>(const solver::ProgramGraph &, ArrayRef<solver::Member>,
                                     solver::Work &);
template footprint::Vector<SmallVector<BindingTime>>
bindingTimesOf<solver::Editor>(const solver::Editor &, ArrayRef<solver::Member>, solver::Work &);

} // namespace idr
