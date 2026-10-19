// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op does besides computing its results: which uses take over the
// reference their value holds, as the op's flow says (lib/IR/Flow.cpp), and
// what taking it over is to every other pass; and what an op, with
// everything in it, does as one asker sees it, read off MLIR's effects
// alone, a call's its own.

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallPtrSet.h"

#include <variant>

using namespace mlir;
using namespace idr;

namespace {

// Whether parameter `index` of `function`, which `use` moves into, takes it
// over: whether it is owned. idr-rc writes the owned grades into the
// signatures, and the program becomes owned, before its placement gives
// the operands their parameters' grades; so while it places, only the
// callee's signature says, and placement asks with the program's table,
// which then decides at any stage. Asked without one, the operand's grade
// answers: a verified call's operand is at its parameter's grade, and
// before idr-rc nothing is owned.
bool ownsParameter(OpOperand &use, FlatSymbolRefAttr function, unsigned index,
                   const SymbolTable *callees) {
  if (!callees)
    return isOwned(use.get().getType());
  return isOwned(callees->lookup<FuncOp>(function.getAttr()).getArgumentTypes()[index]);
}

// Each use of `op` that takes over the reference its value holds, as the
// edges of the reference carrier say: a use the op moves somewhere (into a
// result, a part, a function's result, or a parameter that owns it), a use
// it ends, and the arguments of a dispatch. A forwarded value moves on with
// its reference. A use may be named more than once.
// A unification, a source, a fresh value and a constant name no use.
void eachTaken(Operation *op, const SymbolTable *callees,
               function_ref<void(OpOperand &)> taken) {
  FlowEdges edges;
  flowEdgesOf(op, edges);
  // A use a flow takes over, unless it moves into a parameter that does
  // not own it.
  auto flowed = [&](const FlowEdges::Flow &move) {
    std::optional<OpOperand *> use = move.from.taken();
    if (!use)
      return;
    const auto *param = std::get_if<FlowPoint::Parameter>(&move.to.at);
    if (param && !ownsParameter(**use, param->function, param->index, callees))
      return;
    taken(**use);
  };
  for (const FlowEdges::Edge &edge : edges.edges())
    if (edge.carries(Carrier::Reference))
      std::visit(llvm::makeVisitor(flowed, [](const FlowEdges::Unify &) {},
                                   [](const FlowEdges::Source &) {},
                                   [](const FlowEdges::Fresh &) {},
                                   [&](const FlowEdges::Release &move) { taken(*move.use); },
                                   [](const FlowEdges::Constant &) {},
                                   [&](FlowEdges::Dispatch move) {
                                     MutableOperandRange args =
                                         move.call.getArgOperandsMutable();
                                     for (unsigned i = 0, n = args.size(); i < n; ++i)
                                       taken(args[i]);
                                   }),
                 edge.move);
}

} // namespace

bool idr::consumes(OpOperand &operand, const SymbolTable *callees) {
  bool found = false;
  eachTaken(operand.getOwner(), callees, [&](OpOperand &use) { found |= &use == &operand; });
  return found;
}

// A Free on the reference resource is what keeps an op that takes an owned
// value over from being dropped as dead or merged with another: before
// idr-rc no value is owned, and the op is as free to drop as its other
// effects let it be.
void idr::consumedEffects(
    Operation *op, SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  if (llvm::none_of(op->getOperandTypes(), [](Type type) { return isOwned(type); }))
    return;
  llvm::SmallPtrSet<OpOperand *, 4> freed;
  eachTaken(op, nullptr, [&](OpOperand &use) {
    if (isOwned(use.get().getType()) && freed.insert(&use).second)
      effects.emplace_back(MemoryEffects::Free::get(), &use, ReferenceResource::get());
  });
}

// Upstream's walk gathers the effects: `op`'s own, and those of the ops in
// the regions of every op whose effects are its regions'
// (RecursiveMemoryEffects); any other op's regions are in what it
// declares. No answer, an op that declares nothing and is no such op, may
// do anything. An allocation of a result, the op's own or a nested op's, is
// part of computing it.
Does idr::classify(Operation *op,
                   function_ref<bool(const MemoryEffects::EffectInstance &, Operation *)> touches) {
  std::optional<SmallVector<MemoryEffects::EffectInstance>> effects = getEffectsRecursively(op);
  if (!effects)
    return Does::Touches;
  Does does = Does::Computes;
  for (const MemoryEffects::EffectInstance &effect : *effects) {
    if (touches(effect, op))
      return Does::Touches;
    if (!isa<MemoryEffects::Allocate>(effect.getEffect()) ||
        !isa_and_present<OpResult>(effect.getValue()))
      does = Does::Effects;
  }
  return does;
}

bool idr::onlyAllocates(Operation *op) {
  return classify(op, [](const MemoryEffects::EffectInstance &, Operation *) {
           return false;
         }) == Does::Computes;
}

// A crash and a loop that may not end only write the IO resource, which
// orders them after output without making them output.
bool idr::performsIO(Operation *op) {
  return classify(op, [](const MemoryEffects::EffectInstance &effect, Operation *) {
           return isa<MemoryEffects::Read>(effect.getEffect()) &&
                  isa<IOResource>(effect.getResource());
         }) == Does::Touches;
}

namespace {

// What `value` is the same value as or a part of, back to where it was
// made (sourceOf), itself first.
SmallVector<Value, 4> sourcesOf(Value value) {
  return definitionChain(value, [](Value each) -> std::optional<Value> {
    Source source = sourceOf(each);
    if (const auto *same = std::get_if<Same>(&source))
      return same->value;
    if (const auto *field = std::get_if<Field>(&source))
      return field->scrutinee;
    return std::nullopt;
  });
}

// Whether `value` was made by `call` or after it, by an op of its block
// after it or inside one: nothing the call is given reaches it.
bool madeAfter(Value value, CallOp call) {
  Value made = sourcesOf(value).back();
  Operation *def = made.getDefiningOp();
  if (!def)
    return false;
  Operation *at = call->getBlock()->findAncestorOpInBlock(*def);
  return at && (at == call.getOperation() || call->isBeforeInBlock(at));
}

} // namespace

bool idr::mayRunAt(CallOp call, Operation *at) {
  llvm::SmallPtrSet<Value, 8> read;
  for (Value arg : call.getArgs())
    for (Value value : sourcesOf(arg))
      read.insert(value);
  bool computes = call.getEffects() == Effect::none;
  for (Operation *op = call->getNextNode(); op != at; op = op->getNextNode()) {
    std::optional<SmallVector<MemoryEffects::EffectInstance>> effects = getEffectsRecursively(op);
    if (!effects)
      return false;
    for (const MemoryEffects::EffectInstance &effect : *effects) {
      // IO, a crash or a loop that may not end, ordered with the call's own.
      if (isa<IOResource>(effect.getResource())) {
        if (!computes)
          return false;
        continue;
      }
      if (!isa<MemoryEffects::Write, MemoryEffects::Free>(effect.getEffect()))
        continue;
      // Memory made after the call is no memory it reads.
      Value value = effect.getValue();
      if (value && madeAfter(value, call))
        continue;
      if (!computes || read.contains(value))
        return false;
    }
  }
  return true;
}
