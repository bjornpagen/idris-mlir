// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The functions on a tail call whose result does not fit the return
// registers write it through a pointer instead.

#include "idr/Conversion/PassThroughMemory.h"
#include "idr/Conversion/TailCallPlan.h"

#include "mlir/Dialect/LLVMIR/LLVMDialect.h"
#include "mlir/Interfaces/FunctionInterfaces.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::conversion {

namespace {

// A call of `type`, with `operands`, in place of `call`: its callee, calling
// convention, tail call kind and the attributes of its arguments, the first
// `inserted` arguments new and plain.
LLVM::CallOp recall(RewriterBase &rewriter, LLVM::CallOp call, LLVM::LLVMFunctionType type,
                    ValueRange operands, unsigned inserted) {
  auto fresh = LLVM::CallOp::create(rewriter, call.getLoc(), type, call.getCalleeAttr(), operands);
  fresh.setCConv(call.getCConv());
  fresh.setTailCallKind(call.getTailCallKind());
  if (ArrayAttr attrs = call.getArgAttrsAttr()) {
    SmallVector<Attribute> shifted(inserted, rewriter.getDictionaryAttr({}));
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

void callThroughMemory(LLVM::LLVMFuncOp fn, ArrayRef<TailCallPlan::ThroughMemory> calls,
                       SmallVectorImpl<LLVM::CallOp> &tailCalls, Value out,
                       RewriterBase &rewriter) {
  auto ptr = LLVM::LLVMPointerType::get(fn.getContext());
  for (const TailCallPlan::ThroughMemory &through : calls) {
    LLVM::CallOp call = through.call;
    SmallVector<Value> operands;
    auto planned = llvm::find(tailCalls, call);
    if (planned != tailCalls.end()) {
      operands.push_back(out);
      llvm::append_range(operands, call.getArgOperands());
      rewriter.setInsertionPoint(call);
      LLVM::CallOp fresh = recall(rewriter, call, through.type, operands, 1);
      Operation *ret = call->getNextNode();
      rewriter.setInsertionPoint(ret);
      LLVM::ReturnOp::create(rewriter, ret->getLoc(), ValueRange());
      rewriter.eraseOp(ret);
      rewriter.eraseOp(call);
      *planned = fresh;
      continue;
    }
    Block &entry = fn.getBody().front();
    rewriter.setInsertionPointToStart(&entry);
    Value one = LLVM::ConstantOp::create(rewriter, call.getLoc(), rewriter.getI64Type(),
                                         rewriter.getI64IntegerAttr(1));
    Value slot = LLVM::AllocaOp::create(rewriter, call.getLoc(), ptr, through.result, one, 0);
    operands.push_back(slot);
    llvm::append_range(operands, call.getArgOperands());
    rewriter.setInsertionPoint(call);
    recall(rewriter, call, through.type, operands, 1);
    Value read = LLVM::LoadOp::create(rewriter, call.getLoc(), through.result, slot);
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
