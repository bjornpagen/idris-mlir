// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// An op class's declaration, read as constants: the typed half of the one
// query API. An op's declaration is generated from the specification
// (Generated/Effects.h.inc, Declared<Op>); typed code reads it as a
// constant where the class decides its effects, and applies its typed
// rules to the op's types where they decide. MLIR's interface is
// implemented from it (`declare`), and so is the declared-effects
// interface's default (`declaredEffects`), so no two readers can disagree.
#ifndef IDR_IR_EFFECTS_DECLARED_H
#define IDR_IR_EFFECTS_DECLARED_H

#include "idr/IR/Effects/Rules.h"
#include "idr/IR/Effects/Summarized.h"

#include "mlir/IR/Operation.h"

#include <concepts>
#include <tuple>

namespace idr::effects {

// An op class the specification declares the effects of.
template <class OpT>
concept HasDeclaration = requires {
  { Declared<OpT>::form } -> std::convertible_to<Form>;
};

// An op class that runs where it stands and declares its effects.
template <class OpT>
concept Declares = HasDeclaration<OpT> && Declared<OpT>::form == Form::Declares;

namespace detail {

// One element of an op's typed rules: its effects on the op, as instances,
// as a set, and its most.
template <class Element>
struct RuleOf;

template <Rule R, class Where>
struct RuleOf<ByType<R, Where>> {
  template <class OpT>
  static void emit(OpT op, Instances &effects) { Expand<R, Where>::emit(op, effects); }
  template <class OpT>
  static EffectSet own(OpT op) { return Expand<R, Where>::own(op); }
  static constexpr EffectSet bound() { return Expand<R, Where>::bound(); }
  static constexpr bool decidedByClass = false;
};

template <class Where>
struct RuleOf<Summarized<Where>> {
  template <CarriesRow OpT>
  static void emit(OpT op, Instances &effects) { emitRow(op, effects); }
  template <CarriesRow OpT>
  static EffectSet own(OpT op) { return rowSet(op); }
  static constexpr EffectSet bound() { return anyRow; }
  static constexpr bool decidedByClass = false;
};

template <class Where>
struct RuleOf<HoldsRuntimeMemory<Where>> {
  template <class OpT>
  static void emit(OpT, Instances &) {}
  template <class OpT>
  static EffectSet own(OpT) { return bound(); }
  static constexpr EffectSet bound() {
    EffectSet set;
    set.reported = runtimeMemoryAtoms[RuntimeMemory::Touched];
    return set;
  }
  static constexpr bool decidedByClass = true;
};

template <class OpT>
using Rules = typename Declared<OpT>::Rules;

template <class Tuple>
struct EachRule;
template <class... Element>
struct EachRule<std::tuple<Element...>> {
  template <class OpT>
  static void emit(OpT op, Instances &effects) { (RuleOf<Element>::emit(op, effects), ...); }
  template <class OpT>
  static EffectSet own(OpT op) { return (EffectSet{} | ... | RuleOf<Element>::own(op)); }
  static constexpr EffectSet bound() { return (EffectSet{} | ... | RuleOf<Element>::bound()); }
  static constexpr bool decidedByClass = (true && ... && RuleOf<Element>::decidedByClass);
};

// The op's static effects, as a set.
template <class OpT>
constexpr EffectSet staticSet() {
  EffectSet set;
  for (const Static &each : Declared<OpT>::effects)
    set.add(each.kind, each.resource);
  return set;
}

} // namespace detail

// An op class whose effects its class decides: its declaration's typed
// rules, if any, read no type.
template <class OpT>
concept DecidedByClass = Declares<OpT> && detail::EachRule<detail::Rules<OpT>>::decidedByClass;

// The most an op of the class may do, whatever its types: its static
// effects and every effect its rules may give. Exact when the class decides.
template <Declares OpT>
consteval EffectSet bound() {
  return detail::staticSet<OpT>() | detail::EachRule<detail::Rules<OpT>>::bound();
}

// An op's own effects, not its regions': its class's constant where the
// class decides them, its rules applied to its types where they decide.
template <HasDeclaration OpT>
EffectSet own(OpT op) {
  if constexpr (!Declares<OpT>)
    return EffectSet::everything();
  else if constexpr (DecidedByClass<OpT>)
    return bound<OpT>();
  else
    return detail::staticSet<OpT>() | detail::EachRule<detail::Rules<OpT>>::own(op);
}

// MLIR's `getEffects` of an op whose effects follow from types, which the
// generated definition calls: its static effects and each rule's.
template <Declares OpT>
void declare(OpT op, Instances &effects) {
  for (const Static &each : Declared<OpT>::effects) {
    switch (each.subject.of) {
    case Subject::Of::Op:
      effects.emplace_back(effect(each.kind), resource(each.resource));
      break;
    case Subject::Of::Operand:
      detail::eachOperand(op, each.subject.group, [&](mlir::OpOperand &operand) {
        effects.emplace_back(effect(each.kind), &operand, resource(each.resource));
      });
      break;
    case Subject::Of::Result:
      detail::eachResult(op, each.subject.group, [&](mlir::OpResult result) {
        effects.emplace_back(effect(each.kind), result, resource(each.resource));
      });
      break;
    }
  }
  detail::EachRule<detail::Rules<OpT>>::emit(op, effects);
}

} // namespace idr::effects

namespace idr {

template <class OpT>
effects::EffectSet declaredEffects(OpT op) {
  return effects::own(op);
}

} // namespace idr

#endif // IDR_IR_EFFECTS_DECLARED_H
