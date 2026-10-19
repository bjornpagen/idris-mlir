// RUN: idris-mlir-opt %s --idr-contracts --idr-rc -o %t.mlir
// RUN: %differential %s %t.mlir
// A pass may run passes through its own pipeline, on its own op, and hold
// the op half done between them: idr-rc-exclusive writes the exclusive
// grades of the whole program, then commits them function by function in
// such a run. A contract is a relation at a pass's boundary, so such a pass
// is checked whole, against the program before it. @both stores its
// parameter twice, a reference idr-rc counts once more. The root builds
// the node of the byte it reads, and the counted program prints what the
// program before counting printed, on every byte.
!T = !idr.data<"T", plain [@L(), @N(!idr.box<!idr.data<"T">>, i64, !idr.box<!idr.data<"T">>)]>
idr.program @"nested-run" root(@root) stage(first) {
  idr.func @both(%t: !idr.box<!T>, %k: i64) -> !idr.box<!T> {
    %n = idr.con !idr.box<!T> @N(%t : !idr.box<!T>, %k : i64, %t : !idr.box<!T>)
    return %n : !idr.box<!T>
  }
  idr.func @root(%w0: !idr.world) -> !idr.world {
    %ch, %w = idr.io.get_byte %w0
    %k = arith.extui %ch : i32 to i64
    %leaf = idr.constant !idr.box<!T> #idr.con<!T, @L, []>
    %c1 = arith.constant 1 : i64
    %t0 = idr.call @both(%leaf, %c1) : (!idr.box<!T>, i64) -> !idr.box<!T>
    %t = idr.call @both(%t0, %k) : (!idr.box<!T>, i64) -> !idr.box<!T>
    %s = idr.match %t : !idr.box<!T> -> (i64) {
    case @L() {
      idr.yield %c1 : i64
    }
    case @N(%l: !idr.box<!T>, %x: i64, %r: !idr.box<!T>) {
      idr.yield %x : i64
    }
    }
    %w2 = idr.io.put_sint %s, %w : i64
    return %w2 : !idr.world
  }
}
