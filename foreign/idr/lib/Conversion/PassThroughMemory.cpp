// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions on a tail call whose result does not fit the return
// registers write it through a pointer instead.

#include "idr/Conversion/PassThroughMemory.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// The type of `call`'s callee once it takes a pointer to write its result
// to: that pointer, then what the call passes, and no result. The callee is
// an internal function, never variadic, so the call's operands are its
// parameters.
LLVM::LLVMFunctionType throughPointer(LLVM::CallOp call) {
  MLIRContext *ctx = call.getContext();
  SmallVector<Type> params{LLVM::LLVMPointerType::get(ctx)};
  llvm::append_range(params, call.getArgOperands().getTypes());
  return LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(ctx), params, false);
}

// A call that passes `pointer` first, then what `call` passes, to `call`'s
// callee in its type through a pointer: its calling convention, tail call
// kind and the attributes of its arguments, the pointer's new and plain.
LLVM::CallOp recall(RewriterBase &rewriter, LLVM::CallOp call, Value pointer) {
  SmallVector<Value> operands{pointer};
  llvm::append_range(operands, call.getArgOperands());
  auto fresh = LLVM::CallOp::create(rewriter, call.getLoc(), throughPointer(call),
                                    call.getCalleeAttr(), operands);
  fresh.setCConv(call.getCConv());
  fresh.setTailCallKind(call.getTailCallKind());
  if (ArrayAttr attrs = call.getArgAttrsAttr()) {
    SmallVector<Attribute> shifted{rewriter.getDictionaryAttr({})};
    llvm::append_range(shifted, attrs);
    fresh.setArgAttrsAttr(rewriter.getArrayAttr(shifted));
  }
  return fresh;
}

} // namespace

Value takeResultPointer(LLVM::LLVMFuncOp fn, RewriterBase &rewriter) {
  MLIRContext *ctx = fn.getContext();
  DictionaryAttr attrs = rewriter.getDictionaryAttr(
      rewriter.getNamedAttr(LLVM::LLVMDialect::getNoAliasAttrName(), rewriter.getUnitAttr()));
  (void)cast<FunctionOpInterface>(fn.getOperation())
      .insertArgument(0, LLVM::LLVMPointerType::get(ctx), attrs, fn.getLoc());
  fn.setFunctionType(LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(ctx),
                                                 fn.getFunctionType().getParams(), false));
  fn.removeResAttrsAttr();
  return fn.getArgument(0);
}

void passOnPointer(SmallVectorImpl<LLVM::CallOp> &tailCalls, Value out, RewriterBase &rewriter) {
  for (LLVM::CallOp &call : tailCalls) {
    rewriter.setInsertionPoint(call);
    LLVM::CallOp fresh = recall(rewriter, call, out);
    Operation *ret = call->getNextNode();
    rewriter.setInsertionPoint(ret);
    LLVM::ReturnOp::create(rewriter, ret->getLoc(), ValueRange());
    rewriter.eraseOp(ret);
    rewriter.eraseOp(call);
    call = fresh;
  }
}

void callThroughSlots(LLVM::LLVMFuncOp fn, ArrayRef<LLVM::CallOp> calls, RewriterBase &rewriter) {
  auto ptr = LLVM::LLVMPointerType::get(fn.getContext());
  Block &entry = fn.getBody().front();
  for (LLVM::CallOp call : calls) {
    Type result = call.getResult().getType();
    rewriter.setInsertionPointToStart(&entry);
    Value one = LLVM::ConstantOp::create(rewriter, call.getLoc(), rewriter.getI64Type(),
                                         rewriter.getI64IntegerAttr(1));
    Value slot = LLVM::AllocaOp::create(rewriter, call.getLoc(), ptr, result, one, 0);
    rewriter.setInsertionPoint(call);
    recall(rewriter, call, slot);
    Value read = LLVM::LoadOp::create(rewriter, call.getLoc(), result, slot);
    rewriter.replaceOp(call, read);
  }
}

void storeResults(LLVM::LLVMFuncOp fn, Value out, RewriterBase &rewriter) {
  for (Block &block : fn.getBody()) {
    auto ret = dyn_cast<LLVM::ReturnOp>(block.getTerminator());
    if (!ret || ret.getNumOperands() == 0)
      continue;
    rewriter.setInsertionPoint(ret);
    LLVM::StoreOp::create(rewriter, ret.getLoc(), ret.getOperand(0), out);
    LLVM::ReturnOp::create(rewriter, ret.getLoc(), ValueRange());
    rewriter.eraseOp(ret);
  }
}

} // namespace idr::conversion
