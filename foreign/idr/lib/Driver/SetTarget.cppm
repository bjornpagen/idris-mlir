// idr.driver:settarget: the module's target, written once for the
// compilation.
export module idr.driver:settarget;

import idr.mlir;
import idr.dialect;

export namespace idr::driver {

// The module's target (idr-target), which every step reads: idr-eval's JIT
// compiles for its CPU, so what compile-time evaluation spends does not
// depend on the machine that compiles; idr-lower tells the runtime's entry
// which of its features to test; the object code is compiled for it.
mlir::LogicalResult setTarget(mlir::ModuleOp module) {
  mlir::PassManager pm(module.getContext());
  pm.addPass(idr::createIdrTarget());
  return pm.run(module);
}

} // namespace idr::driver
