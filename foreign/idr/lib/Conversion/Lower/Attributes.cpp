// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the compiler knows of effects, told to LLVM: a function's and a
// call's row, through the effect system's one table of what each atom
// touches and withholds (effects::told), as LLVM's memory effects and its
// function attributes. Nothing here reads an effect its own way.

#include "idr/Conversion/Lower/Lower.h"

#include "mlir/Dialect/LLVMIR/LLVMAttrs.h"
#include "mlir/IR/Builders.h"

using namespace mlir;

namespace idr::conversion {

namespace {

using effects::Access;
using effects::Attribute;
using effects::Location;

LLVM::ModRefInfo modRef(Access access) {
  return access == Access::ReadWrite ? LLVM::ModRefInfo::ModRef : LLVM::ModRefInfo::Ref;
}

// The memory a row may touch, per location LLVM tells apart. Our programs
// touch no target's own memory, which is told what any other memory is.
LLVM::MemoryEffectsAttr memoryOf(MLIRContext *ctx, const effects::Told &told) {
  LLVM::ModRefInfo other = modRef(told.memory[Location::Other]);
  return LLVM::MemoryEffectsAttr::get(
      ctx, {other, modRef(told.memory[Location::ArgMem]),
            modRef(told.memory[Location::InaccessibleMem]),
            modRef(told.memory[Location::ErrnoMem]), other, other});
}

bool tells(const effects::Told &told, Attribute attribute) {
  return !told.withheld.contains(attribute);
}

} // namespace

void tellFunction(LLVM::LLVMFuncOp fn, const effects::Told &told) {
  MLIRContext *ctx = fn.getContext();
  fn.setMemoryEffectsAttr(memoryOf(ctx, told));
  if (tells(told, Attribute::WillReturn))
    fn.setWillReturn(true);
  if (tells(told, Attribute::NoUnwind))
    fn.setNoUnwind(true);
  // The attributes llvm.func has no field for, by their names in LLVM.
  SmallVector<mlir::Attribute> passthrough;
  if (tells(told, Attribute::MustProgress))
    passthrough.push_back(StringAttr::get(ctx, "mustprogress"));
  if (tells(told, Attribute::NoFree))
    passthrough.push_back(StringAttr::get(ctx, "nofree"));
  if (tells(told, Attribute::NoSync))
    passthrough.push_back(StringAttr::get(ctx, "nosync"));
  if (!passthrough.empty())
    fn.setPassthroughAttr(ArrayAttr::get(ctx, passthrough));
}

CallFacts callFacts(MLIRContext *ctx, effects::Row row) {
  effects::Told told = effects::told(row);
  return {memoryOf(ctx, told), told};
}

void tellCall(LLVM::CallOp call, const CallFacts &facts) {
  call.setMemoryEffectsAttr(facts.memory);
  if (tells(facts.told, Attribute::WillReturn))
    call.setWillReturn(true);
  if (tells(facts.told, Attribute::NoUnwind))
    call.setNoUnwind(true);
}

} // namespace idr::conversion
