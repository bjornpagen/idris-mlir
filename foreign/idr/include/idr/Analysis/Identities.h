// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What a function gives back: which component of which argument each
// component of a result is, whenever it returns. Once Idris's indices are erased, a
// function that only rebuilds its argument (Fin's weaken, a term's
// weakening to a larger scope) computes nothing, and a threaded state
// returned inline gives back the fields it was passed. The fact is the
// optimizer's alone: published per result field path to the table its
// passes read (egraph::CalleeFacts), it dies with the optimizer's run.
// idr-simplify replaces a call by the argument part it gives back where
// the call's row allows its deletion (carries neither crash nor
// divergence), and the specializer keys a copy's results by it. The fact
// itself says nothing about returning: a function that never returns gives
// back anything, and deleting its call is the row's to allow, never this
// fact's.
//
// Beside it, what may reach each result on some path: an argument the
// result may be, may hold inside it, or may hold a part of, as a reverse
// accumulator's result is its accumulator on the path that ends and holds
// it on every other. A copy keyed to a weaker hold for a parameter keys
// each result that parameter may reach to that hold too, since the copy
// gives no more there than the parameter claims. This is a sound bound,
// never exact: an op's own result the reading does not see through may
// hold whatever its operands hold, what a region branch forwards into may
// hold whatever enters it, and a value nothing here reads may hold any
// argument.
//
// The functions of one component are found together, in one solve with two
// fixpoints over the same reads. What is given back on every path is the
// greatest: every member starts assumed to give back each argument of its
// result's type, as a whole; a member whose returns do not rebuild one,
// under what is assumed of the rest, loses that assumption. What may reach
// a result is the least: every member starts assumed to let nothing reach
// it, and a member one of whose returns may hold an argument, under what
// is assumed of the rest, gains that fact. Either change puts the members
// that call it back on the queue. Each check can only drop assumptions of
// the one and add facts of the other, each once, and there are finitely
// many of both, so the work ends, and whatever order the members are
// checked in finds the same facts. A callee outside the component is final:
// its facts are read frozen, every field path of them. Each member is read
// once, into a record of how its body builds each value, numbered in walk
// order so one loop over the values ascending reads every value after what
// it is made of; the checks read the record and never walk the body again.
// The solve's work is the values its readings visit: each member's once
// when it is read, and again by each of the two readings at each check and
// when its facts are published. Its records, its queue and its facts are
// the footprint's.
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
// its type fixes, so the path is a place in the value's inline layout.
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

// How much of an argument may reach a result: the argument whole, as the
// result itself or inside it, so the result claims no more of it than the
// argument does; or a part read out of it, of which the argument's claim
// reaches only as far as the part's field lets it, which is at least
// nothing.
enum class Reach : std::uint8_t { Whole, Part };

// On some path that returns, argument `argument` may reach result `result`
// as `reach` says: a part where any path may give one, since a part bounds
// the result's claim no higher than the whole does, and so covers it.
struct MayReach {
  std::uint32_t result;
  std::uint32_t argument;
  Reach reach;
  friend bool operator==(const MayReach &, const MayReach &) = default;
};

// What one function gives back, as a component's solve publishes it: each
// component given back on every path that returns, and what may reach each
// result on some path, sorted by result, then argument, each pair once.
struct FactsView {
  std::span<const GivesBack> givesBack;
  std::span<const MayReach> mayReach;
};
struct Facts {
  footprint::Vector<GivesBack> givesBack;
  footprint::Vector<MayReach> mayReach;
  FactsView view() const { return {givesBack, mayReach}; }
};

// The frozen facts of a callee outside the component being solved.
template <class O>
concept Outside = requires(const O &outside, solver::FunctionId callee) {
  { outside(callee) } -> std::same_as<FactsView>;
};

// The bodies of one component, each read once into its record
// (IdentitiesRecord.cpp), each callee resolved through `editor`, the
// optimizer's thawed graph, and the solve over them (Identities.cpp,
// reading each record's two readings from IdentitiesRebuilds.cpp).
class Component {
public:
  static Component read(const solver::Editor &editor, llvm::ArrayRef<solver::Member> component);

  Component(Component &&) noexcept;
  ~Component();

  // The callees outside the component its bodies call, each once, in the
  // order the solve reads their facts.
  std::span<const solver::FunctionId> outsideCallees() const;

  // The facts of every member, in the component's order, given the frozen
  // facts of each outside callee in outsideCallees' order; the values its
  // readings visited added to `work`.
  footprint::Vector<Facts> solve(std::span<const FactsView> outside, solver::Work &work) &&;

  struct Records;

private:
  explicit Component(std::unique_ptr<Records> records);
  std::unique_ptr<Records> records;
};

// The facts of every member of `component`, in its order: the frozen facts
// each outside callee has are read once, before the solve, whose work is
// added to `work`.
template <Outside O>
footprint::Vector<Facts> givesBackOf(const solver::Editor &editor,
                                     llvm::ArrayRef<solver::Member> component, const O &outside,
                                     solver::Work &work) {
  Component bodies = Component::read(editor, component);
  footprint::Vector<FactsView> frozen;
  for (solver::FunctionId callee : bodies.outsideCallees())
    frozen.push_back(outside(callee));
  return std::move(bodies).solve(frozen, work);
}

} // namespace idr::identities

#endif // IDR_ANALYSIS_IDENTITIES_H
