// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a solver keeps per node, and what may stop a solve. A node's state is
// a value of a join-semilattice, never a container: a solve's state is then
// sized by the problem, one small value per node, and no state is copied
// along an edge.
//
// Two policies, two types. Exact: nothing stops the solve but the lattice's
// height; every analysis a refusal or an ordering fact rests on is exact.
// Budgeted: a count in the program's units may stop it; whatever is not
// finished is written top, so the answer stays sound and the program is
// only less optimized, never refused.
#ifndef IDR_ANALYSIS_SOLVER_LATTICE_H
#define IDR_ANALYSIS_SOLVER_LATTICE_H

#include "idr/Support/Id.h"

#include <concepts>
#include <cstdint>
#include <type_traits>

namespace idr {

template <class L>
concept JoinSemilattice = std::regular<L> && requires(L &a, const L &b) {
  { L::bottom() } -> std::same_as<L>;
  { a.join(b) } -> std::same_as<Changed>;
};

// What a solver keeps per node: a value, never a container.
template <class L>
concept NodeState = JoinSemilattice<L> && std::is_trivially_copyable_v<L> && (sizeof(L) <= 16);

template <class L>
concept FiniteHeight = JoinSemilattice<L> && requires {
  { L::height } -> std::convertible_to<unsigned>;
};

template <class L>
concept Bounded = JoinSemilattice<L> && requires {
  { L::top() } -> std::same_as<L>;
};

// A per-function fact a caller reads: a row, a lifetime signature, a
// borrow mask.
template <class S>
concept Summary = NodeState<S> && FiniteHeight<S>;

struct Exact {};
struct Budgeted {
  // Transfers allowed per member of a component, in the program's units.
  std::uint32_t perMember;
};
template <class P>
concept Policy = std::same_as<P, Exact> || std::same_as<P, Budgeted>;

struct CalleesFirst {};
struct CallersFirst {};
template <class O>
concept Order = std::same_as<O, CalleesFirst> || std::same_as<O, CallersFirst>;

} // namespace idr

#endif // IDR_ANALYSIS_SOLVER_LATTICE_H
