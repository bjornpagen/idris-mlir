// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A typed rule applied to one op: the effects that follow from the type of
// each value of the group it reads, or, for a pair rule, from an operand's
// type and a result's together, from the rule's row of the specification's
// table, as MLIR's instances, as a set, and at most whatever the types. The
// walk over a group's values and the emission of kinds as instances are
// here too, which every expansion of a declaration onto an op's values
// shares.
#ifndef IDR_IR_EFFECTS_RULES_H
#define IDR_IR_EFFECTS_RULES_H

#include "idr/IR/Effects/Set.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"

#include <algorithm>
#include <concepts>
#include <cstddef>
#include <cstdint>
#include <type_traits>
#include <utility>

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

// A one-value rule's row of the specification's table, by part: the kinds
// it gives, the state it gives them on, and where they land.
template <Rule R>
struct Parts {
  template <Part P>
  static constexpr Kinds kinds = P == Part::WhereItHolds ? ruleHolds[R] : ruleFails[R];
  template <Part P>
  static constexpr ResourceId state = P == Part::WhereItHolds ? ruleHoldsOn[R] : ruleFailsOn[R];
  template <Part P>
  static constexpr Landing landing = P == Part::WhereItHolds ? ruleHoldsLanding[R] : ruleFailsLanding[R];

  // A part landing on the value it reads, given on `value`, named by
  // `subject`, where the condition decides for that part.
  template <Part P, class Named, class Give>
    requires(landing<P> == Landing::OnTheValues)
  static void partOnValue(mlir::Value value, Named subject, Give &&give) {
    if constexpr (!kinds<P>.empty())
      if (decides<R>(value) == (P == Part::WhereItHolds))
        give(kinds<P>, state<P>, subject);
  }

  // Both parts on one value, for a rule whose parts land on the value it
  // reads: what a pair rule applies to one side of a pair.
  template <class Named, class Give>
  static void onValue(mlir::Value value, Named subject, Give &&give) {
    partOnValue<Part::WhereItHolds>(value, subject, give);
    partOnValue<Part::WhereItFails>(value, subject, give);
  }

  // Every effect either part may give, whatever the types.
  static constexpr EffectSet bound() {
    EffectSet set;
    for (Kind kind : allOf<Kind>()) {
      if (kinds<Part::WhereItHolds>.contains(kind))
        set.add(kind, state<Part::WhereItHolds>);
      if (kinds<Part::WhereItFails>.contains(kind))
        set.add(kind, state<Part::WhereItFails>);
    }
    return set;
  }
};

// What an expansion gives on an op, from its walk `each`: as MLIR's
// instances, and as a set.
template <class Expansion>
struct Gives {
  template <class OpT>
  static void emit(OpT op, Instances &effects) {
    Expansion::each(op, [&](Kinds kinds, ResourceId state, auto subject) {
      emitKinds(effects, kinds, state, subject);
    });
  }

  template <class OpT>
  static EffectSet own(OpT op) {
    EffectSet set;
    Expansion::each(op, [&](Kinds kinds, ResourceId state, auto) {
      for (Kind kind : allOf<Kind>())
        if (kinds.contains(kind))
          set.add(kind, state);
    });
    return set;
  }
};

// A typed rule's effects on this op. `give` is called with each part's
// kinds, state and subject: the value read, for a part landing on the
// values; each result, for one landing on each result; nothing, for one on
// the state as a whole. A part landing elsewhere than the value read is
// decided by the values read all holding the condition.
template <Rule R, class Where>
struct Expand;

template <Rule R, unsigned G, template <unsigned> class On>
struct Expand<R, On<G>> : Gives<Expand<R, On<G>>> {
  using Read = Group<On<G>>;
  using Of = Parts<R>;

  template <Part P, class OpT, class Give>
  static void part(OpT op, Give &&give) {
    if constexpr (Of::template kinds<P>.empty())
      return;
    else if constexpr (Of::template landing<P> == Landing::OnTheValues)
      Read::each(op, [&](mlir::Value value, auto subject) {
        Of::template partOnValue<P>(value, subject, give);
      });
    else {
      bool allHold = true;
      Read::each(op, [&](mlir::Value value, auto) { allHold = allHold && decides<R>(value); });
      if (allHold != (P == Part::WhereItHolds))
        return;
      if constexpr (Of::template landing<P> == Landing::OnEachResult)
        for (mlir::OpResult result : op->getOpResults())
          give(Of::template kinds<P>, Of::template state<P>, result);
      else
        give(Of::template kinds<P>, Of::template state<P>, nullptr);
    }
  }

  template <class OpT, class Give>
  static void each(OpT op, Give &&give) {
    part<Part::WhereItHolds>(op, give);
    part<Part::WhereItFails>(op, give);
  }

  static constexpr EffectSet bound() { return Of::bound(); }
};

// Which side of a pair a pair rule's one-value rules are applied to.
enum class PairSide : std::uint8_t { Operand, Result };

// A pair rule's effects on this op: each operand of its operand group with
// the result at its position in its result group. Where the relation holds
// of the two types, each one-value rule the pair rule applies to a side
// gives its effects on that side's value; where it fails, the result is the
// operand and nothing is given. Which rules apply is a set known when the
// compiler is built, so each is its own expansion and the rest are none.
template <PairRule P, class Operands, class Results>
struct ExpandPair;

template <PairRule P, unsigned G, unsigned H>
struct ExpandPair<P, OnOperand<G>, OnResult<H>> : Gives<ExpandPair<P, OnOperand<G>, OnResult<H>>> {
  template <PairSide S>
  static constexpr EnumSet<Rule> rulesOn = S == PairSide::Operand ? pairOnOperand[P] : pairOnResult[P];

  template <PairSide S, Rule R, class Named, class Give>
  static void applyOne(mlir::Value value, Named subject, Give &give) {
    if constexpr (rulesOn<S>.contains(R))
      Parts<R>::onValue(value, subject, give);
  }

  template <PairSide S, class Named, class Give>
  static void apply(mlir::Value value, Named subject, Give &give) {
    [&]<std::size_t... I>(std::index_sequence<I...>) {
      (applyOne<S, static_cast<Rule>(I)>(value, subject, give), ...);
    }(std::make_index_sequence<EnumTraits<Rule>::count>{});
  }

  template <class OpT, class Give>
  static void each(OpT op, Give &&give) {
    auto [operands, operandCount] = op.getODSOperandIndexAndLength(G);
    auto [results, resultCount] = op.getODSResultIndexAndLength(H);
    for (unsigned at = 0, pairs = std::min(operandCount, resultCount); at < pairs; ++at) {
      mlir::OpOperand &operand = op->getOpOperand(operands + at);
      mlir::OpResult result = op->getOpResult(results + at);
      if (!relates<pairCondition[P]>(operand.get().getType(), result.getType()))
        continue;
      apply<PairSide::Operand>(operand.get(), &operand, give);
      apply<PairSide::Result>(mlir::Value(result), result, give);
    }
  }

  template <Rule R>
  static constexpr EffectSet boundOf() {
    if constexpr (rulesOn<PairSide::Operand>.contains(R) || rulesOn<PairSide::Result>.contains(R))
      return Parts<R>::bound();
    else
      return EffectSet{};
  }

  static constexpr EffectSet bound() {
    return []<std::size_t... I>(std::index_sequence<I...>) {
      return (EffectSet{} | ... | boundOf<static_cast<Rule>(I)>());
    }(std::make_index_sequence<EnumTraits<Rule>::count>{});
  }
};

} // namespace idr::effects::detail

#endif // IDR_IR_EFFECTS_RULES_H
