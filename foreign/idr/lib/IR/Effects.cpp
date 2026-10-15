// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op does besides computing its results: which uses take over the
// reference their value holds, as the op's flow says (lib/IR/Flow.cpp), and
// what taking it over is to every other pass; and whether an op, with
// everything in it, only computes or may perform IO.

#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/UB/IR/UBOps.h"
#include "llvm/ADT/SmallPtrSet.h"

using namespace mlir;
using namespace idr;

namespace {

// Whether parameter `index` of `function`, which `use` moves into, takes it
// over: whether it is owned. idr-rc writes the owned grades into the
// signatures, and the program becomes owned, before its placement gives
// the operands their parameters' grades; so while it places, only the
// callee's signature says, and placement asks with its table, which then
// decides at any stage. Asked without one, the operand's grade answers: a
// verified call's operand is at its parameter's grade, and before idr-rc
// nothing is owned.
bool ownsParameter(OpOperand &use, FlatSymbolRefAttr function, unsigned index,
                   SymbolTable *symbols) {
  if (!symbols)
    return isOwned(use.get().getType());
  return isOwned(symbols->lookup<FuncOp>(function.getAttr()).getArgumentTypes()[index]);
}

// Each use of `op` that takes over the reference its value holds, as the
// edges of the reference carrier say: a use the op moves somewhere (into a
// result, a part, a function's result, or a parameter that owns it), a use
// it ends, and the arguments of a dispatch. A forwarded value moves on with
// its reference. A use may be named more than once.
void eachTaken(Operation *op, SymbolTable *symbols, function_ref<void(OpOperand &)> taken) {
  FlowEdges edges;
  flowEdgesOf(op, edges);
  for (const FlowEdges::Edge &edge : edges.edges()) {
    if (!edge.carries(Carrier::Reference))
      continue;
    if (edge.kind == FlowEdges::Edge::Kind::Dispatch) {
      MutableOperandRange args = cast<CallOpInterface>(edge.call).getArgOperandsMutable();
      for (unsigned i = 0, n = args.size(); i < n; ++i)
        taken(args[i]);
      continue;
    }
    if (!edge.from.takes())
      continue;
    OpOperand &use = *edge.from.operand;
    if (edge.kind == FlowEdges::Edge::Kind::Flow && edge.to.kind == FlowPoint::Kind::Parameter &&
        !ownsParameter(use, edge.to.function, edge.to.index, symbols))
      continue;
    taken(use);
  }
}

} // namespace

bool idr::consumes(OpOperand &operand, SymbolTable *symbols) {
  bool found = false;
  eachTaken(operand.getOwner(), symbols, [&](OpOperand &use) { found |= &use == &operand; });
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

// What `op` alone does, nested ops aside: nothing, when it has no effects
// or all of them are allocations of its results; IO, when it reads the IO
// resource (a crash and a loop that may not end only write it, which
// orders them after output without making them output); otherwise
// something. An op says so through MemoryEffectOpInterface, even when its
// regions' effects are part of its own (idr.array.update reads and writes
// its array); one that declares nothing has no effects of its own when its
// regions' are its effects, and may do anything when MLIR knows none.
enum class Does { Nothing, IO, Something };

Does does(Operation *op) {
  if (isa<ub::UnreachableOp>(op))
    return Does::Nothing;
  auto iface = dyn_cast<MemoryEffectOpInterface>(op);
  if (!iface)
    return op->hasTrait<OpTrait::HasRecursiveMemoryEffects>() ? Does::Nothing : Does::Something;
  SmallVector<MemoryEffects::EffectInstance> effects;
  iface.getEffects(effects);
  Does out = Does::Nothing;
  for (const MemoryEffects::EffectInstance &effect : effects) {
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
bool anyDoes(Operation *root, function_ref<bool(Does)> stop) {
  return root
      ->walk<WalkOrder::PreOrder>([&](Operation *op) {
        if (stop(does(op)))
          return WalkResult::interrupt();
        return op->hasTrait<OpTrait::HasRecursiveMemoryEffects>() ? WalkResult::advance()
                                                                 : WalkResult::skip();
      })
      .wasInterrupted();
}

} // namespace

bool idr::onlyAllocates(Operation *op) {
  return !anyDoes(op, [](Does what) { return what != Does::Nothing; });
}

bool idr::performsIO(Operation *op) {
  return anyDoes(op, [](Does what) { return what == Does::IO; });
}
