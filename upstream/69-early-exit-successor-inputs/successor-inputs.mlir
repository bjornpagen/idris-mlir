// mlir-opt successor-inputs.mlir -canonicalize
//
// %r is dead. Canonicalizing the scf.if, whose successor mapping includes
// the exit nested in it and so the loop's result, RemoveDeadRegionBranchOp-
// SuccessorInputs erases the operand of the break inside the if; the break
// outside it keeps its operand, and the verifier refuses the loop.
func.func @dead_target_input(%c: i1, %a: i32, %b: i32) {
  %r = scf.loop token(%l) -> i32 {
    scf.if %c {
      scf.break [%l] %a : i32
    }
    scf.break [%l] %b : i32
  }
  return
}
