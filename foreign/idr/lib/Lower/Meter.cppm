// idr.lower:meter: idr-meter, which makes lowered code count the ticks of
// compile-time evaluation's meter. Evaluation's own step: a program is not
// metered.

export module idr.lower:meter;

import idr.mlir;

using namespace mlir;

namespace idr::lower {

// Every evaluation is metered, total code with a larger budget, so every
// function counts a tick when entered, and a loop of code that need not end
// counts one each time round, right before the llvm.sideeffect its
// idr.may_loop lowered to. The tick that exhausts the budget stops the
// call.
export void meterModule(ModuleOp module) {
  MLIRContext *ctx = module.getContext();
  SymbolTable symbols(module);
  auto tick = symbols.lookup<LLVM::LLVMFuncOp>("idris_rt_eval_tick");
  if (!tick) {
    auto b = OpBuilder::atBlockBegin(module.getBody());
    tick = LLVM::LLVMFuncOp::create(b, module.getLoc(), "idris_rt_eval_tick",
                                    LLVM::LLVMFunctionType::get(LLVM::LLVMVoidType::get(ctx), {}));
    symbols.insert(tick);
  }
  OpBuilder b(ctx);
  for (auto fn : module.getOps<func::FuncOp>()) {
    if (fn.isExternal())
      continue;
    b.setInsertionPointToStart(&fn.getBody().front());
    LLVM::CallOp::create(b, fn.getLoc(), tick, ValueRange{});
    fn.walk([&](LLVM::CallIntrinsicOp intrinsic) {
      if (intrinsic.getIntrin() != "llvm.sideeffect")
        return;
      b.setInsertionPoint(intrinsic);
      LLVM::CallOp::create(b, intrinsic.getLoc(), tick, ValueRange{});
    });
  }
}

} // namespace idr::lower
