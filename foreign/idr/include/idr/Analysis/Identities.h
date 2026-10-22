// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a function gives back: which component of which argument each
// component of a result is, whenever it returns. Once Idris's indices are erased, a
// function that only rebuilds its argument (Fin's weaken, a term's
// weakening to a larger scope) computes nothing, and a threaded state
// returned inline gives back the fields it was passed. The fact is held
// once, on idr.func, per result field path; the lowering reads it to give
// back a register it was passed, and idr-simplify replaces a call by the
// argument part it gives back where the call's row allows its deletion
// (carries neither crash nor divergence). The fact itself says nothing
// about returning: a function that never returns gives back anything, and
// deleting its call is the row's to allow, never this fact's.
//
// The functions of one component are found together, as a greatest
// fixpoint: every member starts assumed to give back each argument of its
// result's type, as a whole; a member whose returns do not rebuild one,
// under what is assumed of the rest, loses that assumption, and the
// members that call it are checked again. Each check can only drop an
// assumption, each is dropped once, and there are finitely many, so the
// work ends, and whatever order the members are checked in finds the same
// facts. A callee outside the component is final: its facts are read
// frozen, every field path of them. Each member is read once, into a
// record of how its body builds each value, numbered in walk order so one
// loop over the values ascending reads every value after what it is made
// of; the checks read the record and never walk the body again. The
// solve's work is the values its readings visit: each member's once when
// it is read, and again at each check and when its facts are published.
// Its records, its queue and its facts are the footprint's.
#ifndef IDR_ANALYSIS_IDENTITIES_H
#define IDR_ANALYSIS_IDENTITIES_H

#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Footprint.h"

#include "llvm/ADT/ArrayRef.h"

#include <concepts>
#include <cstdint>
#include <memory>
#include <span>
#include <utility>
#include <variant>

namespace idr::identities {

// A component of a result or of an argument: the value at `index`, then
// down through `fields`, each a field position of a type whose constructor
// its type fixes, so the path is a place in the value's inline layout. The
// shape idr.func's given_back holds (GivenBackAttr), which the optimizer
// writes from these facts.
struct Path {
  std::uint32_t index;
  footprint::Vector<std::uint32_t> fields;
  friend bool operator==(const Path &, const Path &) = default;
};

// On every path that returns, the component `result` of the result is the
// component `argument` of the arguments: the same value.
struct GivesBack {
  Path result;
  Path argument;
  friend bool operator==(const GivesBack &, const GivesBack &) = default;
};
using Facts = footprint::Vector<GivesBack>;

// The frozen facts of a callee outside the component being solved.
template <class O>
concept Outside = requires(const O &outside, solver::FunctionId callee) {
  { outside(callee) } -> std::same_as<std::span<const GivesBack>>;
};

// The bodies of one component, each read once into its record
// (IdentitiesRecord.cpp), and the fixpoint over them (Identities.cpp,
// reading each record's checks from IdentitiesRebuilds.cpp).
class Component {
public:
  template <solver::FunctionNames N>
  static Component read(const N &names, llvm::ArrayRef<solver::Member> component);

  Component(Component &&) noexcept;
  ~Component();

  // The callees outside the component its bodies call, each once, in the
  // order the solve reads their facts.
  std::span<const solver::FunctionId> outsideCallees() const;

  // The facts of every member, in the component's order, given the frozen
  // facts of each outside callee in outsideCallees' order; the values its
  // readings visited added to `work`.
  footprint::Vector<Facts> solve(std::span<const std::span<const GivesBack>> outside,
                                  solver::Work &work) &&;

  struct Records;

private:
  explicit Component(std::unique_ptr<Records> records);
  std::unique_ptr<Records> records;
};

extern template Component Component::read<solver::ProgramGraph>(const solver::ProgramGraph &,
                                                                llvm::ArrayRef<solver::Member>);
extern template Component Component::read<solver::Editor>(const solver::Editor &,
                                                          llvm::ArrayRef<solver::Member>);

// The facts of every member of `component`, in its order: the frozen facts
// each outside callee has are read once, before the solve, whose work is
// added to `work`.
template <solver::FunctionNames N, Outside O>
footprint::Vector<Facts> givesBackOf(const N &names, llvm::ArrayRef<solver::Member> component,
                                     const O &outside, solver::Work &work) {
  Component bodies = Component::read(names, component);
  footprint::Vector<std::span<const GivesBack>> frozen;
  for (solver::FunctionId callee : bodies.outsideCallees())
    frozen.push_back(outside(callee));
  return std::move(bodies).solve(frozen, work);
}

} // namespace idr::identities

#endif // IDR_ANALYSIS_IDENTITIES_H
