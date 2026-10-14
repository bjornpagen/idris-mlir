// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What of a function may point into its frame.

#include "idr/Conversion/Frame.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>

using namespace mlir;

namespace idr::conversion {

bool Frame::mayPoint(Type type) {
  if (isa<LLVM::LLVMPointerType>(type))
    return true;
  if (auto structure = dyn_cast<LLVM::LLVMStructType>(type))
    return llvm::any_of(structure.getBody(), mayPoint);
  if (auto array = dyn_cast<LLVM::LLVMArrayType>(type))
    return mayPoint(array.getElementType());
  return false;
}

Frame::Frame(LLVM::LLVMFuncOp fn) {
  SmallVector<Value> work;
  auto add = [&](Value value) {
    if (value && bound.insert(value).second)
      work.push_back(value);
  };
  fn.walk([&](LLVM::AllocaOp slot) { add(slot.getResult()); });
  while (!work.empty()) {
    Value value = work.pop_back_val();
    for (OpOperand &use : value.getUses()) {
      Operation *user = use.getOwner();
      if (auto branch = dyn_cast<BranchOpInterface>(user)) {
        if (std::optional<BlockArgument> arg =
                branch.getSuccessorBlockArgument(use.getOperandNumber()))
          add(*arg);
        continue;
      }
      if (auto load = dyn_cast<LLVM::LoadOp>(user)) {
        if (load.getAddr() == value && mayPoint(load.getType()))
          add(load.getResult());
        continue;
      }
      if (isa<LLVM::GEPOp, LLVM::AddrSpaceCastOp, LLVM::SelectOp, LLVM::InsertValueOp,
              LLVM::ExtractValueOp, LLVM::IntToPtrOp, LLVM::PtrToIntOp>(user))
        for (Value result : user->getResults())
          add(result);
    }
  }
  fn.walk([&](LLVM::StoreOp store) {
    leaked |= bound.contains(store.getValue()) && !bound.contains(store.getAddr());
  });
}

bool Frame::reachedBy(LLVM::CallOp call) const {
  return leaked || llvm::any_of(call.getArgOperands(),
                                [&](Value arg) { return bound.contains(arg); });
}

} // namespace idr::conversion
