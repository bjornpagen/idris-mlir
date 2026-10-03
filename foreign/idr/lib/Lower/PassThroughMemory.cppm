// idr.lower:passThroughMemory: the functions on a tail call whose result
// does not fit the return registers write it through a pointer instead.

export module idr.lower:passThroughMemory;

import idr.mlir;

using namespace mlir;

namespace idr::lower {

namespace {

// A call of `callee`, of type `type`, with `operands`, in place of `call`:
// its calling convention and the attributes of its arguments, the first
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

// Each function of `inMemory` takes a pointer to write its result to, first,
// and returns nothing. A call of one in `tailCalls`, right before the return
// of its result, passes on the pointer its caller got (its caller returns the
// same type, so it is in `inMemory` too); any other passes a slot of its
// caller's frame and reads the result from it. `tailCalls` follows the calls
// as they are made again.
void passThroughMemory(ModuleOp module, const SetVector<Operation *> &inMemory,
                       DenseSet<Operation *> &tailCalls, RewriterBase &rewriter) {
  if (inMemory.empty())
    return;
  MLIRContext *ctx = module.getContext();
  auto ptr = LLVM::LLVMPointerType::get(ctx);
  auto nothing = LLVM::LLVMVoidType::get(ctx);
  DenseMap<Operation *, Type> results;
  for (Operation *op : inMemory) {
    auto fn = cast<LLVM::LLVMFuncOp>(op);
    LLVM::LLVMFunctionType type = fn.getFunctionType();
    results[fn] = type.getReturnType();
    DictionaryAttr attrs = rewriter.getDictionaryAttr(
        rewriter.getNamedAttr(LLVM::LLVMDialect::getNoAliasAttrName(), rewriter.getUnitAttr()));
    (void)cast<FunctionOpInterface>(fn.getOperation()).insertArgument(0, ptr, attrs, fn.getLoc());
    fn.setFunctionType(
        LLVM::LLVMFunctionType::get(nothing, fn.getFunctionType().getParams(), false));
    fn.removeResAttrsAttr();
  }
  // Every call of such a function, in the new signature.
  SmallVector<LLVM::CallOp> calls;
  module.walk([&](LLVM::CallOp call) {
    FlatSymbolRefAttr name = call.getCalleeAttr();
    if (name && inMemory.contains(module.lookupSymbol(name.getAttr())))
      calls.push_back(call);
  });
  for (LLVM::CallOp call : calls) {
    auto callee = cast<LLVM::LLVMFuncOp>(module.lookupSymbol(call.getCalleeAttr().getAttr()));
    Type result = results.lookup(callee);
    auto caller = call->getParentOfType<LLVM::LLVMFuncOp>();
    SmallVector<Value> operands;
    if (tailCalls.contains(call)) {
      operands.push_back(caller.getArgument(0));
      llvm::append_range(operands, call.getArgOperands());
      rewriter.setInsertionPoint(call);
      LLVM::CallOp fresh = recall(rewriter, call, callee.getFunctionType(), operands, 1);
      Operation *ret = call->getNextNode();
      rewriter.setInsertionPoint(ret);
      LLVM::ReturnOp::create(rewriter, ret->getLoc(), ValueRange());
      rewriter.eraseOp(ret);
      rewriter.eraseOp(call);
      tailCalls.erase(call);
      tailCalls.insert(fresh);
      continue;
    }
    Block &entry = caller.getBody().front();
    rewriter.setInsertionPointToStart(&entry);
    Value one = LLVM::ConstantOp::create(rewriter, call.getLoc(), rewriter.getI64Type(),
                                         rewriter.getI64IntegerAttr(1));
    Value slot = LLVM::AllocaOp::create(rewriter, call.getLoc(), ptr, result, one, 0);
    operands.push_back(slot);
    llvm::append_range(operands, call.getArgOperands());
    rewriter.setInsertionPoint(call);
    recall(rewriter, call, callee.getFunctionType(), operands, 1);
    Value read = LLVM::LoadOp::create(rewriter, call.getLoc(), result, slot);
    rewriter.replaceOp(call, read);
  }
  // The other returns write the result.
  for (Operation *op : inMemory) {
    auto fn = cast<LLVM::LLVMFuncOp>(op);
    Value out = fn.getArgument(0);
    SmallVector<LLVM::ReturnOp> returns;
    fn.walk([&](LLVM::ReturnOp ret) { returns.push_back(ret); });
    for (LLVM::ReturnOp ret : returns) {
      if (ret.getNumOperands() == 0)
        continue;
      rewriter.setInsertionPoint(ret);
      LLVM::StoreOp::create(rewriter, ret.getLoc(), ret.getOperand(0), out);
      LLVM::ReturnOp::create(rewriter, ret.getLoc(), ValueRange());
      rewriter.eraseOp(ret);
    }
  }
}

} // namespace idr::lower
