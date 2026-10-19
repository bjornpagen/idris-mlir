// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --canonicalize --idr-expect=holds=lowered,loops=@spin:1 -o /dev/null
// RUN: %differential %s %t.mlir
// idr.may_loop, which idr-tail-loops puts in the loops of functions that
// are not total, becomes an effect in the loop's body that no MLIR pass
// removes and LLVM keeps in place, and that emits no instruction. So an
// unused loop that may not terminate stays. It is still the loop it was:
// the root spins on the byte it reads, and on 0, whose loop ends at once,
// the program, lowered and as written, ends alike (%differential, on that
// input alone: on any other the loop never ends, which
// pipeline-endless-loop shows of a whole program).
// STDIN: \0000
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
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    idr.call @spin(%n) : (i64) -> ()
    return %w1 : !idr.world
  }
}
