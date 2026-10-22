// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one query API of the effect system. Every reader of an op's effects
// asks here: typed code reads its op class's declaration as a constant
// where the class decides it; an `Operation *` makes one interface
// dispatch, ours (an op's own effects as one set) or, for an op of another
// dialect, upstream's, whose instances are folded once into a set. Nothing
// else names a state, reads an effect list, or maps effects to atoms.
//
// An op's declaration is generated from the specification
// (Generated/Effects.h.inc, Declared<Op>); MLIR's interface is implemented
// from it, and so is every answer here, so no two readers can disagree.
#ifndef IDR_IR_EFFECTS_QUERY_H
#define IDR_IR_EFFECTS_QUERY_H

#include "idr/IR/Effects/Set.h"
#include "idr/IR/Func.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <functional>
#include <tuple>
#include <type_traits>

namespace idr::effects {

//===----------------------------------------------------------------------===//
// The typed path
//===----------------------------------------------------------------------===//

// An op class the specification declares the effects of.
template <class OpT>
concept HasDeclaration = requires {
  { Declared<OpT>::form } -> std::convertible_to<Form>;
};

// An op class that runs where it stands and declares its effects.
template <class OpT>
concept Declares = HasDeclaration<OpT> && Declared<OpT>::form == Form::Declares;

namespace detail {

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

// A call: the row it carries, and its copy of its callee's write part, a
// write in place it declares on each operand its callee writes through.
template <class CallOpT>
concept CarriesRow = HoldsWritePart<CallOpT> && requires(CallOpT call) {
  { call.getRow() } -> std::convertible_to<Row>;
};

// A call's set: each ordering atom's call effects on its state, the atoms
// that only report kept as reported, and a write in place for an operand
// its callee writes through. Its row comes back out of the set whole.
template <CarriesRow OpT>
EffectSet rowSet(OpT op) {
  EffectSet set;
  Row row = op.getRow();
  for (Atom atom : allOf<Atom>())
    if (row.contains(atom))
      for (Kind kind : allOf<Kind>())
        if (atomCallKinds[atom].contains(kind))
          set.add(kind, atomState[atom]);
  set.reported = row & reportsOnly;
  ::idr::forEachWritten(op, [&](mlir::OpOperand &) { set.add(Kind::Write, ResourceId::Contents); });
  return set;
}

template <CarriesRow OpT>
void emitRow(OpT op, Instances &effects) {
  Row row = op.getRow();
  for (Atom atom : allOf<Atom>())
    if (row.contains(atom))
      emitKinds(effects, atomCallKinds[atom], atomState[atom], nullptr);
  ::idr::forEachWritten(op, [&](mlir::OpOperand &operand) {
    effects.emplace_back(effect<Kind::Write>(), &operand, resource<ResourceId::Contents>());
  });
}

// Every atom's call effects and every atom that only reports: the most a
// call may declare.
inline constexpr EffectSet anyRow = [] {
  EffectSet set;
  for (Atom atom : allOf<Atom>())
    for (Kind kind : allOf<Kind>())
      if (atomCallKinds[atom].contains(kind))
        set.add(kind, atomState[atom]);
  set.reported = reportsOnly;
  set.add(Kind::Write, ResourceId::Contents);
  return set;
}();

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

//===----------------------------------------------------------------------===//
// The untyped path
//===----------------------------------------------------------------------===//

// An op's own effects, not its regions': through our interface for an op
// of ours, through upstream's for an op of another dialect, its instances
// folded into a set; an op with neither may do anything, unless its effects
// are its regions' alone.
EffectSet own(mlir::Operation *op);

// An op's effects with everything in each region whose effects are its op's
// (MLIR's recursive memory effects), folded in one walk.
EffectSet whole(mlir::Operation *op);

// What `op`, with everything in it, adds to its function's row: its
// effects summarized, a call's row whole among them. Where in memory an
// effect lands, which the function's own derivation refines, is not read.
inline Row rowOf(mlir::Operation *op) { return whole(op).row(); }

// One effect with the value it names, for the questions about one value.
struct Effect {
  Kind kind;
  ResourceId resource;
  // The value the effect names; none for an effect on a state as a whole.
  mlir::Value value;
};

// One of MLIR's effect instances, in the tree's terms: its kind, the state
// it names, its value. An effect of another dialect on the root through a
// value is on memory a value holds, as the specification's `valueMemory`
// says.
Effect effectOf(const mlir::MemoryEffects::EffectInstance &instance);

// What one effect summarizes as in a function's row.
constexpr Row project(const Effect &each) { return project(each.kind, each.resource); }

// What an op reports in its function's row beyond its MLIR effects: the
// memory its runtime function, or a call's callee, acquires or gives back
// that no value names.
Row reportedBy(mlir::Operation *op);

// What an op, with everything in it, does toward one asker's question:
// nothing it asks about; or something it asks about, or what MLIR cannot
// say.
enum class Does : std::uint8_t { Avoids, Touches };

// A question about single effects.
template <class Q>
concept Question = std::predicate<const Q &, const Effect &>;

namespace detail {

// Whether an op's regions' effects are its own.
inline bool recursive(mlir::Operation *op) {
  return op->hasTrait<mlir::OpTrait::HasRecursiveMemoryEffects>();
}

// How a walk over effects ended: every effect visited, or stopped, by its
// visitor or at an op that says nothing MLIR can read, which may do
// anything.
enum class Walked : std::uint8_t { All, Stopped };

template <class Visit>
concept EffectVisitor = requires(Visit &visit, const Effect &each) {
  { visit(each) } -> std::same_as<Walked>;
};

// Each effect of `op` and of everything in its regions whose effects are
// its own, while `visit` asks for more.
template <EffectVisitor Visit>
Walked eachEffect(mlir::Operation *op, Visit &&visit) {
  Walked walked = Walked::All;
  op->walk<mlir::WalkOrder::PreOrder>([&](mlir::Operation *nested) {
    auto memory = llvm::dyn_cast<mlir::MemoryEffectOpInterface>(nested);
    if (!memory && !recursive(nested)) {
      walked = Walked::Stopped;
      return mlir::WalkResult::interrupt();
    }
    if (memory) {
      llvm::SmallVector<mlir::MemoryEffects::EffectInstance, 4> instances;
      memory.getEffects(instances);
      for (const mlir::MemoryEffects::EffectInstance &instance : instances)
        if (visit(effectOf(instance)) == Walked::Stopped) {
          walked = Walked::Stopped;
          return mlir::WalkResult::interrupt();
        }
    }
    return recursive(nested) ? mlir::WalkResult::advance() : mlir::WalkResult::skip();
  });
  return walked;
}

} // namespace detail

// The one classifier: what `op` does toward the question `touches`.
template <Question Q>
Does classify(mlir::Operation *op, const Q &touches) {
  detail::Walked walked = detail::eachEffect(op, [&](const Effect &each) {
    return std::invoke(touches, each) ? detail::Walked::Stopped : detail::Walked::All;
  });
  return walked == detail::Walked::All ? Does::Avoids : Does::Touches;
}

// Whether `operand`'s op takes over the reference its value holds: it frees
// the count of that operand. Read off the op's own declaration, a call's
// included, never its callee's.
bool consumes(mlir::OpOperand &operand);

// Whether `op` allocates `value`, a fresh value of its own.
bool allocates(mlir::Operation *op, mlir::Value value);

// Whether `moved`, with everything in it, may run on the other side of
// `across`, with everything in it: neither may tell.
inline bool mayMoveAcross(mlir::Operation *moved, mlir::Operation *across) {
  return !whole(moved).conflicts(whole(across));
}

} // namespace idr::effects

namespace idr {

template <class OpT>
effects::EffectSet declaredEffects(OpT op) {
  return effects::own(op);
}

} // namespace idr

#endif // IDR_IR_EFFECTS_QUERY_H
