// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.call and idr.return. A call's callee is read once per module verify,
// from the collection MLIR shares among every symbol user, and nowhere
// else: what a call may do is its own `effects`, which idr-effects writes
// from its callee's and from what the closures it is given may do, and
// what it takes over is its operands' grades, which the callee's
// parameters are. So canonicalize, CSE and remove-dead-values ask a call
// from any thread, and the answer costs its operands and results.
//
// IO is a read and a write of the IO resource, as the idr.io ops declare
// it; a possible crash writes the crash resource and a function that may
// not return the divergence resource, each with a write of the IO resource
// too, as idr.crash and idr.may_loop declare theirs, so that neither
// moves, merges, goes, or is reordered with output. A result that is not a
// scalar is a fresh value the call allocates on the lin resource (no heap,
// a value no pass may merge with another, as idr.lin.enter declares its
// own), which keeps CSE from merging two calls that make cells and still
// lets an unused one go.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Grades.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

using namespace mlir;
using namespace idr;

namespace {

// What a call or a function may do: its effects, or everything when it
// has none, which no writer stores.
Effect mayDo(EffectAttr effects) {
  return effects ? effects.getValue() : Effect::io | Effect::crash | Effect::diverge;
}

} // namespace

LogicalResult idr::CallOp::verifySymbolUses(SymbolTableCollection &symbols) {
  FlatSymbolRefAttr name = getCalleeAttr();
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(getOperation(), name);
  if (!fn)
    return emitOpError("calls ") << name << ", which the module does not define as an idr.func";
  // Each operand's type is its parameter's, grade included, so that what
  // the call takes over is read from the call alone.
  ArrayRef<Type> inputs = fn.getArgumentTypes();
  if (getArgs().size() != inputs.size())
    return emitOpError("passes ") << getArgs().size() << " arguments to " << name
                                  << ", which takes " << inputs.size();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(getArgs().getTypes(), inputs)))
    if (std::get<0>(pair) != std::get<1>(pair))
      return emitOpError("passes ") << std::get<0>(pair) << " as argument " << index << " of "
                                    << name << ", which takes " << std::get<1>(pair);
  ArrayRef<Type> results = fn.getResultTypes();
  if (getNumResults() != results.size())
    return emitOpError("expects ") << getNumResults() << " results from " << name
                                   << ", which returns " << results.size();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(getResultTypes(), results)))
    if (std::get<0>(pair) != std::get<1>(pair))
      return emitOpError("expects ") << std::get<0>(pair) << " as result " << index << " of "
                                     << name << ", which returns " << std::get<1>(pair);
  // A call says at least what its callee may do: the callee's facts are
  // the authority, the call's a copy that idr-effects keeps.
  EffectAttr carried = getEffectsAttr();
  if (!carried)
    return success();
  Effect callee = mayDo(fn.isExternal() ? EffectAttr() : fn.getEffectsAttr());
  if (!bitEnumContainsAll(carried.getValue(), callee))
    return emitOpError("carries effects ")
           << carried << ", but " << name << " may do " << EffectAttr::get(getContext(), callee);
  return success();
}

void idr::CallOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  Effect bits = mayDo(getEffectsAttr());
  bool io = bitEnumContainsAll(bits, Effect::io);
  bool crash = bitEnumContainsAll(bits, Effect::crash);
  bool diverge = bitEnumContainsAll(bits, Effect::diverge);
  if (io) {
    effects.emplace_back(MemoryEffects::Read::get(), IOResource::get());
    effects.emplace_back(MemoryEffects::Write::get(), IOResource::get());
  }
  if (crash)
    effects.emplace_back(MemoryEffects::Write::get(), CrashResource::get());
  if (diverge)
    effects.emplace_back(MemoryEffects::Write::get(), DivergenceResource::get());
  if ((crash || diverge) && !io)
    effects.emplace_back(MemoryEffects::Write::get(), IOResource::get());
  consumedEffects(getOperation(), effects);
  for (OpResult result : getOperation()->getResults()) {
    Type type = unrestricted(result.getType());
    if (!type.isIntOrIndexOrFloat() && !isWorld(type))
      effects.emplace_back(MemoryEffects::Allocate::get(), result, LinResource::get());
  }
}

// The callee takes over an argument whose parameter it owns, and the
// operand's type is that parameter's.
bool idr::CallOp::consumesOperand(unsigned number) {
  return isOwned(getOperation()->getOperand(number).getType());
}

LogicalResult idr::ReturnOp::verify() {
  auto fn = cast<FuncOp>((*this)->getParentOp());
  auto name = FlatSymbolRefAttr::get(fn.getSymNameAttr());
  ArrayRef<Type> results = fn.getResultTypes();
  if (getNumOperands() != results.size())
    return emitOpError("returns ") << getNumOperands() << " values, but " << name << " returns "
                                   << results.size();
  for (auto [index, pair] : llvm::enumerate(llvm::zip_equal(getOperandTypes(), results)))
    if (std::get<0>(pair) != std::get<1>(pair))
      return emitOpError("returns ") << std::get<0>(pair) << " as result " << index << ", but "
                                     << name << " returns " << std::get<1>(pair);
  return success();
}
