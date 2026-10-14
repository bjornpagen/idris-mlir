// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What an op does besides computing its results: where a use takes over
// the reference its value holds, as the op that uses it declares, and what
// taking it over is to every other pass; the effects of IO on buffers and
// arrays; and whether an op, with everything in it, only computes or may
// perform IO.

#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/SCF/IR/SCF.h"
#include "mlir/Dialect/UB/IR/UBOps.h"

using namespace mlir;
using namespace idr;

bool idr::consumes(OpOperand &operand, SymbolTable *symbols) {
  Operation *op = operand.getOwner();
  // A call takes an argument over unless the callee borrows the parameter:
  // a borrowed one is a view, plain, where one the callee takes is owned.
  // Before idr-rc grades the signatures no parameter is owned yet, and
  // idr-rc's reuse insertion, which runs then, takes every call to consume
  // its arguments itself; idr-rc reads the callee's grade through its table
  // while the operands are not yet retyped to it.
  if (symbols)
    if (auto call = dyn_cast<CallOp>(op)) {
      auto fn = symbols->lookup<FuncOp>(call.getCalleeAttr().getAttr());
      unsigned index = operand.getOperandNumber();
      return !fn || index >= fn.getArgumentTypes().size() ||
             isOwned(fn.getArgumentTypes()[index]);
    }
  if (auto consuming = dyn_cast<ConsumingOpInterface>(op))
    return consuming.consumesOperand(operand.getOperandNumber());
  // What a loop carries into its next iteration or out of it moves on with
  // its references. A counted loop's bounds and step are indices.
  if (isa<scf::YieldOp, scf::WhileOp>(op))
    return true;
  if (auto loop = dyn_cast<scf::ForOp>(op))
    return operand.getOperandNumber() >= loop.getNumControlOperands();
  if (auto condition = dyn_cast<scf::ConditionOp>(op))
    return &operand != &condition.getConditionMutable();
  return false;
}

// A Free on the reference resource is what keeps an op that takes an owned
// value over from being dropped as dead or merged with another: before
// idr-rc no value is owned, and the op is as free to drop as its other
// effects let it be.
void idr::consumedEffects(
    Operation *op, SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  for (OpOperand &operand : op->getOpOperands())
    if (isOwned(operand.get().getType()) && consumes(operand))
      effects.emplace_back(MemoryEffects::Free::get(), &operand, ReferenceResource::get());
}

// The IO of an op on a buffer or an array is in the world's order, as every
// other IO op's.
void idr::ioEffects(Value allocated,
                    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  effects.emplace_back(MemoryEffects::Read::get(), IOResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), IOResource::get());
  if (allocated)
    effects.emplace_back(MemoryEffects::Allocate::get(), cast<OpResult>(allocated),
                         SideEffects::DefaultResource::get());
}

namespace {

// What `op` alone does, nested ops aside: nothing, when it has no effects
// or all of them are allocations of its results; IO, when it reads the IO
// resource (a crash and a loop that may not end only write it, which
// orders them after output without making them output); otherwise
// something. An op whose effects MLIR does not know may do anything.
enum class Does { Nothing, IO, Something };

Does does(Operation *op) {
  if (op->hasTrait<OpTrait::HasRecursiveMemoryEffects>() || isa<ub::UnreachableOp>(op))
    return Does::Nothing;
  auto iface = dyn_cast<MemoryEffectOpInterface>(op);
  if (!iface)
    return Does::Something;
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

} // namespace

bool idr::onlyAllocates(Operation *op) {
  return !op->walk([](Operation *inner) {
              return does(inner) == Does::Nothing ? WalkResult::advance()
                                                  : WalkResult::interrupt();
            })
              .wasInterrupted();
}

bool idr::performsIO(Operation *op) {
  return op->walk([](Operation *inner) {
             return does(inner) == Does::IO ? WalkResult::interrupt() : WalkResult::advance();
           })
      .wasInterrupted();
}
