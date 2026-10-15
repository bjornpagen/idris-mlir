// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr.call and idr.return. A call's callee is read through a symbol table:
// once per module verify, from the collection MLIR shares among every
// symbol user, and by every pass that asks what a call may do
// (idr::effectsOf). The callee's effects are the one copy; the call holds
// none. What a call takes over is its flow's: each argument moves into its
// callee's parameter, which owns it or not.
//
// To a question asked without a symbol table, the effects an upstream pass
// reads off the op, a call may do anything a function may: IO, a read and a
// write of the IO resource as the idr.io ops declare it; a crash, a write
// of the crash resource; and not returning, a write of the divergence
// resource, as idr.crash and idr.may_loop declare theirs. So no such pass
// drops, merges or reorders a call; the passes that know the callee do,
// through effectsOf.

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
        args, /*arg_attrs=*/nullptr, /*res_attrs=*/nullptr);
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
  return success();
}

void idr::CallOp::getEffects(
    SmallVectorImpl<SideEffects::EffectInstance<MemoryEffects::Effect>> &effects) {
  effects.emplace_back(MemoryEffects::Read::get(), IOResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), IOResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), CrashResource::get());
  effects.emplace_back(MemoryEffects::Write::get(), DivergenceResource::get());
  consumedEffects(getOperation(), effects);
}

Effect idr::effectsOf(CallOpInterface call, SymbolTableCollection &symbols) {
  auto name = dyn_cast<SymbolRefAttr>(call.getCallableForCallee());
  if (!name)
    return anyEffect;
  auto fn = symbols.lookupNearestSymbolFrom<FuncOp>(call.getOperation(), name);
  if (!fn || !fn.getEffectsAttr())
    return anyEffect;
  return fn.getEffectsAttr().getValue();
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
