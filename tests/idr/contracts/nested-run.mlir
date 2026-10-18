// NEEDS-ACCEPTANCE: that idr-rc keeps its contracts under --idr-contracts, step by step: idr-rc-exclusive commits the grades it wrote through its own pipeline, on its own op, and that run is part of its run, not checked against the program; and that this module parses with its constant written type first.
// RUN: idris-mlir-opt %s --idr-contracts --idr-rc -o /dev/null
// A pass may run passes through its own pipeline, on its own op, and hold
// the op half done between them: idr-rc-exclusive writes the exclusive
// grades of the whole program, then commits them function by function in
// such a run. A contract is a relation at a pass's boundary, so such a pass
// is checked whole, against the program before it. @both stores its
// parameter twice, a reference idr-rc counts once more.
!T = !idr.data<"T", plain [@L(), @N(!idr.box<!idr.data<"T">>, i64, !idr.box<!idr.data<"T">>)]>
idr.program @"nested-run" root(@root) stage(first) {
  idr.func @both(%t: !idr.box<!T>, %k: i64) -> !idr.box<!T> {
    %n = idr.con !idr.box<!T> @N(%t : !idr.box<!T>, %k : i64, %t : !idr.box<!T>)
    return %n : !idr.box<!T>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %leaf = idr.constant !idr.box<!T> #idr.con<!T, @L, []>
    %c1 = arith.constant 1 : i64
    %t = idr.call @both(%leaf, %c1) : (!idr.box<!T>, i64) -> !idr.box<!T>
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
