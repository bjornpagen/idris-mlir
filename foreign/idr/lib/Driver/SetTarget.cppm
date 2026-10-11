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
  // The parser has just verified every operation. idr-target and the two
  // passes it runs write the module's target attributes and leave every
  // function as it was, so verifying inside this pass manager would walk
  // the whole module three times before the pipeline. The module operation
  // is verified once the attributes are written; a later step verifies a
  // function when it changes that function.
  pm.enableVerifier(false);
  pm.addPass(idr::createIdrTarget());
  if (mlir::failed(pm.run(module)))
    return mlir::failure();
  return mlir::verify(module, /*verifyRecursively=*/false);
}

} // namespace idr::driver
