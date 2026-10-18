// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.call and idr.return. A call holds what it may do, its `effects`, as
// llvm.call holds its memory effects, and declares to MLIR what they stand
// for, so every pass, upstream's among them, reads a call alone. Its
// symbol-use verifier, run once per verification of its program from the
// collection MLIR shares among every symbol user, holds the call to its
// callee: its types are the callee's signature, and its effects contain the
// callee's. What a call takes over is its flow's: each argument moves into
// its callee's parameter, which owns it or not.

#include "idr/IR/Func.h"

#include "idr/IR/Grades.h"

#include "mlir/IR/BuiltinTypes.h"
#include "mlir/IR/SymbolTable.h"
#include "mlir/Interfaces/SideEffectInterfaces.h"

using namespace mlir;
using namespace idr;

void idr::CallOp::build(OpBuilder &builder, OperationState &state, FuncOp callee,
                        ValueRange args) {
  build(builder, state, callee.getResultTypes(), FlatSymbolRefAttr::get(callee.getSymNameAttr()),
        args, /*arg_attrs=*/nullptr, /*res_attrs=*/nullptr, callee.getEffects());
}

LogicalResult idr::CallOp::verifySymbolUses(SymbolTableCollection &symbols) {
  FlatSymbolRefAttr name = getCalleeAttr();
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(getOperation(), name);
  if (!fn)
    return emitOpError("calls ") << name << ", which the program does not define as an idr.func";
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
  // What the call may do is at least what its callee may, so that what a
  // pass reads off the call alone never says too little.
  if (!bitEnumContainsAll(getEffects(), fn.getEffects()))
    return emitOpError("holds the effects ")
           << stringifyEffect(getEffects()) << ", which do not contain those of " << name
           << ": " << stringifyEffect(fn.getEffects() & ~getEffects());
  return success();
}

// What its effects stand for, then what it takes over, then a fresh value
// for each linear result, which no pass may merge with another's (CSE keeps
// two calls that each give one) and which a call nothing uses may still drop
// (an allocation of its own result).
void idr::CallOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  effectInstances(getEffects(), effects);
  consumedEffects(getOperation(), effects);
  for (OpResult result : getResults())
    if (isLinear(result.getType()))
      effects.emplace_back(MemoryEffects::Allocate::get(), result, LinResource::get());
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
