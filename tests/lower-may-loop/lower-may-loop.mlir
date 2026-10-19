// RUN: idris-mlir-opt %s --idr-lower --canonicalize --idr-expect=holds=lowered,loops=@spin:1 -o /dev/null
// idr.may_loop, which idr-tail-loops puts in the loops of functions that
// are not total, becomes an effect in the loop's body that no MLIR pass
// removes and LLVM keeps in place, and that emits no instruction. So an
// unused loop that may not terminate stays.
idr.program @"may-loop" root(@Prog.main) stage(owned) {
  idr.func @spin(%n: i64) {
    %r = scf.while (%x = %n) : (i64) -> i64 {
      %zero = arith.constant 0 : i64
      %more = arith.cmpi ne, %x, %zero : i64
      scf.condition(%more) %x : i64
    } do {
    ^bb0(%x: i64):
      idr.may_loop
      scf.yield %x : i64
    }
    return
  }
  idr.func @Prog.main() -> i64 {
    %one = arith.constant 1 : i64
    idr.call @spin(%one) : (i64) -> ()
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
