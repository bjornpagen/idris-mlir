// mlir-opt region-inliner.mlir -canonicalize
//
// The scf.if has one region successor path: then-region, then the break's
// successor, the loop's results. computeSingleAcyclicRegionBranchPath
// follows it into the loop, an op InlineRegionBranchOp does not own.
func.func @inline_through_exit(%v: i32) -> i32 {
  %true = arith.constant true
  %r = scf.loop token(%l) -> i32 {
    scf.if %true {
      scf.break [%l] %v : i32
    }
    scf.break [%l] %v : i32
  }
  return %r : i32
}
