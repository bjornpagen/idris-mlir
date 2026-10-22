// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A typed rule applied to one op: the effects that follow from the type of
// each value of the group it reads, from the rule's row of the
// specification's table, as MLIR's instances, as a set, and at most
// whatever the types. The walk over a group's values and the emission of
// kinds as instances are here too, which every expansion of a declaration
// onto an op's values shares.
#ifndef IDR_IR_EFFECTS_RULES_H
#define IDR_IR_EFFECTS_RULES_H

#include "idr/IR/Effects/Set.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"

#include <concepts>
#include <cstddef>
#include <cstdint>
#include <type_traits>

namespace idr::effects::detail {

// The values of a group of `op`, as the operands or results MLIR's effect
// instances name.
template <class OpT, std::invocable<mlir::OpOperand &> Visit>
void eachOperand(OpT op, unsigned group, Visit &&visit) {
  auto [start, length] = op.getODSOperandIndexAndLength(group);
  for (unsigned at = start; at < start + length; ++at)
    visit(op->getOpOperand(at));
}

template <class OpT, std::invocable<mlir::OpResult> Visit>
void eachResult(OpT op, unsigned group, Visit &&visit) {
  auto [start, length] = op.getODSResultIndexAndLength(group);
  for (unsigned at = start; at < start + length; ++at)
    visit(op->getOpResult(at));
}

template <class Where>
struct Group;
template <unsigned G>
struct Group<OnOperand<G>> {
  template <class OpT, class Visit>
  static void each(OpT op, Visit &&visit) {
    eachOperand(op, G, [&](mlir::OpOperand &operand) { visit(operand.get(), &operand); });
  }
};
template <unsigned G>
struct Group<OnResult<G>> {
  template <class OpT, class Visit>
  static void each(OpT op, Visit &&visit) {
    eachResult(op, G, [&](mlir::OpResult result) { visit(mlir::Value(result), result); });
  }
};

// Whether a rule's condition holds of `value`'s type.
template <Rule R>
bool decides(mlir::Value value) {
  return holds<ruleCondition[R]>(value.getType());
}

// Emits the kinds of `kinds` on `state`, on `subject`: an operand, a result,
// or the state as a whole.
template <class Named>
void emitKinds(Instances &effects, Kinds kinds, ResourceId state, Named subject) {
  for (Kind kind : allOf<Kind>()) {
    if (!kinds.contains(kind))
      continue;
    if constexpr (std::is_same_v<Named, std::nullptr_t>)
      effects.emplace_back(effect(kind), resource(state));
    else
      effects.emplace_back(effect(kind), subject, resource(state));
  }
}

// Which part of a rule: what it gives where its condition holds, or where
// it fails.
enum class Part : std::uint8_t { WhereItHolds, WhereItFails };

// A typed rule's effects on this op. `give` is called with each part's
// kinds, state and subject: the value read, for a part landing on the
// values; each result, for one landing on each result; nothing, for one on
// the state as a whole. A part landing elsewhere than the value read is
// decided by the values read all holding the condition.
template <Rule R, class Where>
struct Expand;

template <Rule R, unsigned G, template <unsigned> class On>
struct Expand<R, On<G>> {
  using Read = Group<On<G>>;

  template <Part P>
  static constexpr Kinds kindsOf = P == Part::WhereItHolds ? ruleHolds[R] : ruleFails[R];
  template <Part P>
  static constexpr ResourceId stateOf = P == Part::WhereItHolds ? ruleHoldsOn[R] : ruleFailsOn[R];
  template <Part P>
  static constexpr Landing landingOf = P == Part::WhereItHolds ? ruleHoldsLanding[R] : ruleFailsLanding[R];

  template <Part P, class OpT, class Give>
  static void part(OpT op, Give &&give) {
    if constexpr (kindsOf<P>.empty())
      return;
    else if constexpr (landingOf<P> == Landing::OnTheValues)
      Read::each(op, [&](mlir::Value value, auto subject) {
        if (decides<R>(value) == (P == Part::WhereItHolds))
          give(kindsOf<P>, stateOf<P>, subject);
      });
    else {
      bool allHold = true;
      Read::each(op, [&](mlir::Value value, auto) { allHold = allHold && decides<R>(value); });
      if (allHold != (P == Part::WhereItHolds))
        return;
      if constexpr (landingOf<P> == Landing::OnEachResult)
        for (mlir::OpResult result : op->getOpResults())
          give(kindsOf<P>, stateOf<P>, result);
      else
        give(kindsOf<P>, stateOf<P>, nullptr);
    }
  }

  template <class OpT, class Give>
  static void each(OpT op, Give &&give) {
    part<Part::WhereItHolds>(op, give);
    part<Part::WhereItFails>(op, give);
  }

  template <class OpT>
  static void emit(OpT op, Instances &effects) {
    each(op, [&](Kinds kinds, ResourceId state, auto subject) { emitKinds(effects, kinds, state, subject); });
  }

  template <class OpT>
  static EffectSet own(OpT op) {
    EffectSet set;
    each(op, [&](Kinds kinds, ResourceId state, auto) {
      for (Kind kind : allOf<Kind>())
        if (kinds.contains(kind))
          set.add(kind, state);
    });
    return set;
  }

  static constexpr EffectSet bound() {
    EffectSet set;
    for (Kind kind : allOf<Kind>()) {
      if (kindsOf<Part::WhereItHolds>.contains(kind))
        set.add(kind, stateOf<Part::WhereItHolds>);
      if (kindsOf<Part::WhereItFails>.contains(kind))
        set.add(kind, stateOf<Part::WhereItFails>);
    }
    return set;
  }
};

} // namespace idr::effects::detail

#endif // IDR_IR_EFFECTS_RULES_H
