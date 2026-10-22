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

#include "llvm/ADT/BitVector.h"
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

// What `value` is in `fn`: an entry argument is its parameter; what
// idr::sourceOf finds the same value is what that value is; anything else
// is anything. The chain is followed by a loop, never by recursion.
Source sourceIn(Value value, FuncOp fn) {
  for (;;) {
    if (auto arg = dyn_cast<BlockArgument>(value); arg && arg.getParentRegion() == &fn.getBody())
      return FromParameter{arg.getArgNumber()};
    idr::Source source = sourceOf(value);
    auto *same = std::get_if<idr::Same>(&source);
    if (!same)
      return FromAnything{};
    value = same->value;
  }
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
  std::vector<Edge> edges;
  std::vector<std::uint32_t> edgeStart;
  std::vector<Source> sources;
  std::vector<std::uint32_t> slot;
};

template <solver::FunctionNames N>
Calls readCalls(const N &names, ArrayRef<solver::Member> component) {
  // The members by id, to place a callee: a sorted list, searched, never a
  // map of the program's functions by name.
  std::vector<std::pair<std::uint32_t, std::uint32_t>> byId;
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
    out.slot.push_back(slots);
    slots += member.fn.getNumArguments();
    out.edgeStart.push_back(static_cast<std::uint32_t>(out.edges.size()));
    FuncOp fn = member.fn;
    fn.getBody().walk([&](CallOp call) {
      std::optional<std::uint32_t> callee = positionOf(names.id(call.getCalleeAttr()));
      if (!callee)
        return;
      auto first = static_cast<std::uint32_t>(out.sources.size());
      for (Value operand : call.getArgs())
        out.sources.push_back(sourceIn(operand, fn));
      out.edges.push_back({static_cast<std::uint32_t>(at), *callee, first,
                           static_cast<std::uint32_t>(out.sources.size()) - first});
    });
  }
  out.slot.push_back(slots);
  out.edgeStart.push_back(static_cast<std::uint32_t>(out.edges.size()));
  return out;
}

// The binding times of the root's parameters: the flat solve from the root,
// each member pushed when it is first reached or one of its nodes rises,
// then each call of the root read against its own position.
SmallVector<BindingTime> solveRoot(const Calls &calls, ArrayRef<solver::Member> component,
                                   std::uint32_t root) {
  std::vector<Abstract> value(calls.slot.back());
  auto members = static_cast<unsigned>(component.size());
  llvm::BitVector reached(members), queued(members);
  std::vector<std::uint32_t> work;
  auto at = [&](std::uint32_t member, std::uint32_t param) -> Abstract & {
    return value[calls.slot[member] + param];
  };
  auto passed = [&](const Edge &edge, std::uint32_t arg) {
    return std::visit(llvm::makeVisitor([&](FromParameter from) { return at(edge.caller, from.param); },
                                        [](FromAnything) { return Abstract{Kind::Anything, 0}; }),
                      calls.sources[edge.firstSource + arg]);
  };
  for (std::uint32_t p = 0; p < component[root].fn.getNumArguments(); ++p)
    at(root, p) = {Kind::Same, p};
  reached.set(root);
  queued.set(root);
  work.push_back(root);
  while (!work.empty()) {
    std::uint32_t caller = work.back();
    work.pop_back();
    queued.reset(caller);
    for (std::uint32_t e = calls.edgeStart[caller]; e < calls.edgeStart[caller + 1]; ++e) {
      const Edge &edge = calls.edges[e];
      bool rose = !reached.test(edge.callee);
      reached.set(edge.callee);
      for (std::uint32_t arg = 0; arg < edge.sources; ++arg) {
        Abstract &into = at(edge.callee, arg);
        Abstract joined = join(into, passed(edge, arg));
        if (joined != into) {
          into = joined;
          rose = true;
        }
      }
      if (rose && !queued.test(edge.callee)) {
        queued.set(edge.callee);
        work.push_back(edge.callee);
      }
    }
  }

  SmallVector<BindingTime> times(component[root].fn.getNumArguments(), BindingTime::Fixed);
  for (const Edge &edge : calls.edges) {
    if (edge.callee != root || !reached.test(edge.caller))
      continue;
    for (std::uint32_t arg = 0; arg < edge.sources; ++arg)
      if (passed(edge, arg) != Abstract{Kind::Same, arg})
        times[arg] = BindingTime::Varies;
  }
  return times;
}

} // namespace

template <solver::FunctionNames N>
std::vector<SmallVector<BindingTime>> bindingTimesOf(const N &names,
                                                     ArrayRef<solver::Member> component) {
  Calls calls = readCalls(names, component);
  std::vector<SmallVector<BindingTime>> out;
  out.reserve(component.size());
  for (std::uint32_t root = 0; root < component.size(); ++root)
    out.push_back(solveRoot(calls, component, root));
  return out;
}

template std::vector<SmallVector<BindingTime>>
bindingTimesOf<solver::ProgramGraph>(const solver::ProgramGraph &, ArrayRef<solver::Member>);
template std::vector<SmallVector<BindingTime>>
bindingTimesOf<solver::Editor>(const solver::Editor &, ArrayRef<solver::Member>);

} // namespace idr
