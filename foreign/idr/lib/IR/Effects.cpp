// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op does besides computing its results: which uses take over the
// reference their value holds, as the op's flow says (lib/IR/Flow.cpp), and
// what taking it over is to every other pass; and whether an op, with
// everything in it, only computes or may perform IO, a call counted as its
// callee's effects where the asker gives the program's symbol table.

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
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
// callee's signature says, and placement asks with the program's table
// (CalleeEffects), which then decides at any stage. Asked without one, the
// operand's grade answers: a verified call's operand is at its parameter's
// grade, and before idr-rc nothing is owned.
bool ownsParameter(OpOperand &use, FlatSymbolRefAttr function, unsigned index,
                   const CalleeEffects *callees) {
  if (!callees)
    return isOwned(use.get().getType());
  return isOwned(
      callees->symbols.lookup<FuncOp>(function.getAttr()).getArgumentTypes()[index]);
}

// Each use of `op` that takes over the reference its value holds, as the
// edges of the reference carrier say: a use the op moves somewhere (into a
// result, a part, a function's result, or a parameter that owns it), a use
// it ends, and the arguments of a dispatch. A forwarded value moves on with
// its reference. A use may be named more than once.
// A unification, a source, a fresh value and a constant name no use.
void eachTaken(Operation *op, const CalleeEffects *callees,
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

bool idr::consumes(OpOperand &operand, const CalleeEffects *callees) {
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

namespace {

// The bit of a function's `effects` that a call's effect on `resource`
// stands for, as the idr.io ops, idr.crash and idr.may_loop declare theirs
// and idr.call declares every one; none for any other resource, such as a
// reference the call consumes, which is the call's own.
std::optional<Effect> bitOf(SideEffects::Resource *resource) {
  if (resource == IOResource::get())
    return Effect::io;
  if (resource == CrashResource::get())
    return Effect::crash;
  if (resource == DivergenceResource::get())
    return Effect::diverge;
  return std::nullopt;
}

// What a run of `call`'s callee may do, when `callees` names it: its entry,
// which is anything until a pass has found less. A callee that is a value,
// or a function the table does not hold as an idr.func, is none the table
// names.
std::optional<Effect> calleeEffect(CallOpInterface call, const CalleeEffects *callees) {
  if (!callees)
    return std::nullopt;
  auto name =
      dyn_cast_if_present<FlatSymbolRefAttr>(dyn_cast<SymbolRefAttr>(call.getCallableForCallee()));
  if (!name)
    return std::nullopt;
  auto fn = callees->symbols.lookup<FuncOp>(name.getAttr());
  if (!fn)
    return std::nullopt;
  return fn.getEffects();
}

} // namespace

std::optional<SmallVector<MemoryEffects::EffectInstance>>
idr::ownEffects(Operation *op, const CalleeEffects *callees) {
  SmallVector<MemoryEffects::EffectInstance> effects;
  if (isa<ub::UnreachableOp>(op))
    return effects;
  auto iface = dyn_cast<MemoryEffectOpInterface>(op);
  if (!iface) {
    if (op->hasTrait<OpTrait::HasRecursiveMemoryEffects>())
      return effects;
    return std::nullopt;
  }
  iface.getEffects(effects);
  if (auto call = dyn_cast<CallOpInterface>(op))
    if (std::optional<Effect> callee = calleeEffect(call, callees))
      llvm::erase_if(effects, [&](const MemoryEffects::EffectInstance &effect) {
        std::optional<Effect> bit = bitOf(effect.getResource());
        return bit && !bitEnumContainsAny(*callee, *bit);
      });
  return effects;
}

namespace {

// What `op` alone does, nested ops aside: nothing, when it has no effects
// or all of them are allocations of its results; IO, when it reads the IO
// resource (a crash and a loop that may not end only write it, which
// orders them after output without making them output); otherwise
// something. An op says so through MemoryEffectOpInterface, even when its
// regions' effects are part of its own (idr.array.update reads and writes
// its array); one that declares nothing has no effects of its own when its
// regions' are its effects, and may do anything when MLIR knows none.
enum class Does { Nothing, IO, Something };

Does does(Operation *op, const CalleeEffects *callees) {
  std::optional<SmallVector<MemoryEffects::EffectInstance>> effects = ownEffects(op, callees);
  if (!effects)
    return Does::Something;
  Does out = Does::Nothing;
  for (const MemoryEffects::EffectInstance &effect : *effects) {
    if (effect.getResource() == IOResource::get() && isa<MemoryEffects::Read>(effect.getEffect()))
      return Does::IO;
    if (!isa<MemoryEffects::Allocate>(effect.getEffect()) ||
        !isa_and_present<OpResult>(effect.getValue()))
      out = Does::Something;
  }
  return out;
}

// Whether `stop` holds of what some op whose effects are part of `root`'s
// does: `root` itself, and the ops in the regions of every such op whose
// effects include its regions' (RecursiveMemoryEffects), as upstream's
// getEffectsRecursively gathers them. Any other op's regions are in what
// it declares.
bool anyDoes(Operation *root, const CalleeEffects *callees, function_ref<bool(Does)> stop) {
  return root
      ->walk<WalkOrder::PreOrder>([&](Operation *op) {
        if (stop(does(op, callees)))
          return WalkResult::interrupt();
        return op->hasTrait<OpTrait::HasRecursiveMemoryEffects>() ? WalkResult::advance()
                                                                 : WalkResult::skip();
      })
      .wasInterrupted();
}

} // namespace

bool idr::onlyAllocates(Operation *op, const CalleeEffects *callees) {
  return !anyDoes(op, callees, [](Does what) { return what != Does::Nothing; });
}

bool idr::performsIO(Operation *op, const CalleeEffects *callees) {
  return anyDoes(op, callees, [](Does what) { return what == Does::IO; });
}
