// NEEDS-ACCEPTANCE: that idr-rc keeps its contracts under --idr-contracts: the steps it runs on the program through its own pipeline, between which the program is graded owned and not yet counted, are part of its run and are not checked against that program.
// RUN: idris-mlir-opt %s --idr-contracts --idr-rc -o /dev/null
// A pass may run passes through its own pipeline, on its own op, and hold
// the op half done between them: idr-rc grades every value owned and sets
// the owned stage, then places the counts in such a run. A contract is a
// relation at a pass's boundary, so idr-rc is checked whole, against the
// program before it. @both stores its parameter twice, a reference idr-rc
// counts once more, so the program between the grading and the counting
// holds a reference consumed twice, which the owned stage refuses.
!T = !idr.data<"T", plain [@L(), @N(!idr.box<!idr.data<"T">>, i64, !idr.box<!idr.data<"T">>)]>
idr.program @"nested-run" root(@root) stage(first) {
  idr.func @both(%t: !idr.box<!T>, %k: i64) -> !idr.box<!T> {
    %n = idr.con !idr.box<!T> @N(%t : !idr.box<!T>, %k : i64, %t : !idr.box<!T>)
    return %n : !idr.box<!T>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %leaf = idr.constant #idr.con<!T, @L, []> : !idr.box<!T>
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
    %w2 = idr.io.put_int signed %s, %w : i64
    return %w2 : !idr.world
  }
}
