// NEEDS-ACCEPTANCE: that idr-rc's steps are passes MLIR's tools name and run: --mlir-print-ir-after=idr-rc-place prints each function as idr-rc-place left it, and idr-rc-place run without idr-rc-grades before it refuses, naming the Reuses it reads.
// RUN: idris-mlir-opt %s --idr-rc --mlir-disable-threading --mlir-print-ir-after=idr-rc-place -o /dev/null 2> %t.after
// RUN: FileCheck %s --check-prefix=AFTER < %t.after
// RUN: sed -n 's|^// GRADED: ||p' %s > %t.graded.mlir
// RUN: %status 1 idris-mlir-opt %t.graded.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-place)))' -o /dev/null 2> %t.alone
// RUN: FileCheck %s --check-prefix=ALONE < %t.alone
// idr-rc is a pipeline of passes, each a step a tool can name: after
// idr-rc-place, @bump builds its new cell in the one its list left. A step
// reads what an earlier one decided from its program's analyses: placed
// alone, on a program no idr-rc-grades decided reuses for, idr-rc-place
// has nothing to read and says so (the GRADED program, at the stage
// idr-rc-grades leaves).
// AFTER: IR Dump After IdrRcPlace (idr-rc-place)
// AFTER: idr.cell.recycle
// ALONE: error: internal error: idr-rc-place: no Reuses of the program
// GRADED: idr.program @alone root(@root) stage(graded) {
// GRADED:   idr.func @root() -> i64 {
// GRADED:     %z = arith.constant 0 : i64
// GRADED:     return %z : i64
// GRADED:   }
// GRADED: }
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @steps root(@root) stage(first) {
  idr.func @bump(%l: !idr.box<!L>) -> !idr.box<!L> {
    %n = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %c1 = arith.constant 1 : i64
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      idr.yield %n : !idr.box<!L>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %h2 = arith.addi %h, %c1 : i64
      %t2 = idr.call @bump(%t) : (!idr.box<!L>) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%h2 : i64, %t2 : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %x = arith.constant 7 : i64
    %n = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
    %l = idr.con !idr.box<!L> @C(%x : i64, %n : !idr.box<!L>)
    %b = idr.call @bump(%l) : (!idr.box<!L>) -> !idr.box<!L>
    %s = idr.match %b : !idr.box<!L> -> (i64) {
    case @N() {
      idr.yield %x : i64
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      idr.yield %h : i64
    }
    }
    %w2 = idr.io.put_sint %s, %w : i64
    return %w2 : !idr.world
  }
}
