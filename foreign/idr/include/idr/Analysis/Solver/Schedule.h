// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one static schedule of a solve over the program graph's components:
// callees first or callers first, in waves, a component's wave one past the
// latest wave of a component it reads, each wave run by MLIR's
// parallelForEach on the context's pool. Every solve over components whose
// units are dear runs on it: Ranges (one dataflow solve per function) and
// the local rule (InPlace/Unique.cpp). The rows' join, one union per
// component, is a serial pass over the components (rows::joinComponents).
//
// A solve on it writes only its own component's entries and reads only
// finished components' and its own: a component's unit alone writes its
// members, and a wave starts only when the one before it has returned. So
// components run in parallel with no lock and no state of ours shared
// between threads: the threads and their ordering are MLIR's, which also
// orders a wave's diagnostics by the component's place in it. What each
// writes is what a serial run in the schedule's order writes:
// byte-identical at any thread count. A wave waits for its slowest
// component, the price of keeping every synchronization upstream's. Its
// tables, indexed by component, are the footprint's.
#ifndef IDR_ANALYSIS_SOLVER_SCHEDULE_H
#define IDR_ANALYSIS_SOLVER_SCHEDULE_H

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/Support/Footprint.h"
#include "idr/Support/Id.h"

#include "mlir/IR/MLIRContext.h"
#include "mlir/IR/Threading.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <concepts>
#include <cstdint>
#include <ranges>
#include <span>
#include <type_traits>

namespace idr {

struct CalleesFirst {};
struct CallersFirst {};
template <class O>
concept Order = std::same_as<O, CalleesFirst> || std::same_as<O, CallersFirst>;

} // namespace idr

namespace idr::solver {

namespace detail {

// Each component a component reads, in the schedule's direction: those of
// its members' callees, or of its members' callers; never itself. A
// component read by several calls is visited once per call.
template <Order O, class Visit>
void forEachRead(const ProgramGraph &g, SccId c, Visit &&visit) {
  for (FunctionId f : g.members(c)) {
    if constexpr (std::same_as<O, CalleesFirst>) {
      for (const Call &call : g.callees(f))
        if (SccId read = g.sccOf(call.callee); read != c)
          visit(read);
    } else {
      for (FunctionId caller : g.callers(f))
        if (SccId read = g.sccOf(caller); read != c)
          visit(read);
    }
  }
}

// Every component in the schedule's order: ids ascending callees first,
// descending callers first. Every component a component reads comes before
// it.
template <Order O, class Visit>
void inOrder(const ProgramGraph &g, Visit &&visit) {
  auto ids = g.sccCount().ids();
  if constexpr (std::same_as<O, CalleesFirst>) {
    for (SccId c : ids)
      visit(c);
  } else {
    for (SccId c : std::views::reverse(ids))
      visit(c);
  }
}

// Each component's wave: 0 when it reads no other component, else one past
// the latest wave of a component it reads, which the schedule's order has
// already given its wave.
template <Order O>
IndexVector<SccId, std::uint32_t> wavesOf(const ProgramGraph &g) {
  IndexVector<SccId, std::uint32_t> wave(g.sccCount(), 0);
  inOrder<O>(g, [&](SccId c) {
    std::uint32_t at = 0;
    forEachRead<O>(g, c, [&](SccId read) { at = std::max<std::uint32_t>(at, wave[read] + 1); });
    wave[c] = at;
  });
  return wave;
}

} // namespace detail

// Runs `solve` on every component of `g`, each after every component it
// reads, and adds the steps each returns to `work` once every component has
// run. Each component's steps are kept in its own slot and summed in id
// order, so no unit adds to `work` from another thread.
template <Order O, class Solve>
  requires std::invocable<const Solve &, SccId> &&
           std::same_as<std::invoke_result_t<const Solve &, SccId>, std::uint64_t>
void inSchedule(const ProgramGraph &g, mlir::MLIRContext &context, Work &work,
                const Solve &solve) {
  Count<SccId> sccs = g.sccCount();
  IndexVector<SccId, std::uint32_t> wave = detail::wavesOf<O>(g);
  // The components wave by wave, each wave in the schedule's order.
  footprint::Vector<SccId> order;
  order.reserve(sccs.value());
  detail::inOrder<O>(g, [&](SccId c) { order.push_back(c); });
  llvm::stable_sort(order, [&](SccId a, SccId b) { return wave[a] < wave[b]; });

  IndexVector<SccId, std::uint64_t> steps(sccs, 0);
  for (std::span<const SccId> rest(order); !rest.empty();) {
    std::uint32_t now = wave[rest.front()];
    auto end = std::ranges::find_if(rest, [&](SccId c) { return wave[c] != now; });
    std::span<const SccId> members = rest.first(static_cast<std::size_t>(end - rest.begin()));
    mlir::parallelForEach(&context, members, [&](SccId c) { steps[c] = solve(c); });
    rest = rest.subspan(members.size());
  }
  std::uint64_t total = 0;
  for (SccId c : sccs.ids())
    total += steps[c];
  work.add(total);
}

} // namespace idr::solver

#endif // IDR_ANALYSIS_SOLVER_SCHEDULE_H
