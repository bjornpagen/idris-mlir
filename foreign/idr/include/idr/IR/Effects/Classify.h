// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// One effect with the value it names, and the one classifier over single
// effects: a question about one value (does an op read it, does anything
// in it write) walks MLIR's instances of an op and of everything in its
// regions whose effects are its own, each read in the tree's terms. An op
// that says nothing MLIR can read may do anything, so the walk stops there
// and the classifier answers that it touches. The walk's step, one op's own
// instances, is the API's too: a function's walk that already visits every
// op reads each op once through it, where asking the whole walk of each op
// would read every nested op again for each of its ancestors.
#ifndef IDR_IR_EFFECTS_CLASSIFY_H
#define IDR_IR_EFFECTS_CLASSIFY_H

#include "idr/IR/Effects/Vocabulary.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <functional>

namespace idr::effects {

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

// What an op, with everything in it, does toward one asker's question:
// nothing it asks about; or something it asks about, or what MLIR cannot
// say.
enum class Does : std::uint8_t { Avoids, Touches };

// A question about single effects.
template <class Q>
concept Question = std::predicate<const Q &, const Effect &>;

// How a walk over effects ended: every effect visited, or stopped, by its
// visitor or at an op that says nothing MLIR can read, which may do
// anything.
enum class Walked : std::uint8_t { All, Stopped };

template <class Visit>
concept EffectVisitor = requires(Visit &visit, const Effect &each) {
  { visit(each) } -> std::same_as<Walked>;
};

namespace detail {

// Whether an op's regions' effects are its own.
inline bool recursive(mlir::Operation *op) {
  return op->hasTrait<mlir::OpTrait::HasRecursiveMemoryEffects>();
}

} // namespace detail

// Each effect `op` itself declares, not its regions', while `visit` asks
// for more. An op that says nothing MLIR can read is one of two different
// ops: one whose effects are its regions' alone, which a walk reads op by
// op, and one that may do anything.
template <EffectVisitor Visit>
Walked eachOwnEffect(mlir::Operation *op, Visit &&visit) {
  auto memory = llvm::dyn_cast<mlir::MemoryEffectOpInterface>(op);
  if (!memory)
    return detail::recursive(op) ? Walked::All : Walked::Stopped;
  llvm::SmallVector<mlir::MemoryEffects::EffectInstance, 4> instances;
  memory.getEffects(instances);
  for (const mlir::MemoryEffects::EffectInstance &instance : instances)
    if (visit(effectOf(instance)) == Walked::Stopped)
      return Walked::Stopped;
  return Walked::All;
}

namespace detail {

// Each effect of `op` and of everything in its regions whose effects are
// its own, while `visit` asks for more.
template <EffectVisitor Visit>
Walked eachEffect(mlir::Operation *op, Visit &&visit) {
  mlir::WalkResult walked = op->walk<mlir::WalkOrder::PreOrder>([&](mlir::Operation *nested) {
    if (eachOwnEffect(nested, visit) == Walked::Stopped)
      return mlir::WalkResult::interrupt();
    return recursive(nested) ? mlir::WalkResult::advance() : mlir::WalkResult::skip();
  });
  return walked.wasInterrupted() ? Walked::Stopped : Walked::All;
}

} // namespace detail

// The one classifier: what `op` does toward the question `touches`.
template <Question Q>
Does classify(mlir::Operation *op, const Q &touches) {
  Walked walked = detail::eachEffect(op, [&](const Effect &each) {
    return std::invoke(touches, each) ? Walked::Stopped : Walked::All;
  });
  return walked == Walked::All ? Does::Avoids : Does::Touches;
}

} // namespace idr::effects

#endif // IDR_IR_EFFECTS_CLASSIFY_H
