// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// RUN: idris-mlir-opt %s --idr-target --idr-pipeline -o %t.lowered.mlir
// RUN: grep -q 'llvm.call @idris_rt_dec(' %t.lowered.mlir
// RUN: sed '/llvm.call @idris_rt_dec(/d' %t.lowered.mlir > %t.leaks.mlir
// RUN: not %differential %s %t.leaks.mlir 2>&1 | FileCheck %s --check-prefix=LEAKS
// Every cell a program allocates is freed by the time it ends, whichever
// way the counting went: a list mapped in place, a list read and then
// consumed, a shared list mapped into fresh cells while it is still read
// afterwards, and lists of which only the head is used. The input byte
// sets the lists' lengths, 0 to 12 and 0 to 2, so every length from the
// empty list on is run, and every run is held to no cell live at its end,
// before counting (the whole pipeline) and after it. The same program with
// every release taken out of its lowered form prints the same, and leaves
// cells live: the differential names it on the first input, the empty
// one, which reads as 0xff, lists of 8 and 0 cells.
// LEAKS: differential: {{.*}}leaks.mlir leaves {{[1-9][0-9]*}} cells live on the empty input
!L = !idr.data<"L">
#types = #idr.types<
  "L" = list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]
>
idr.program @live root(@Prog.main) stage(higher) types #types {
  idr.func @build(%n: i64) -> !idr.box<!L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!L>) {
    case 0 {
      %e = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
      idr.yield %e : !idr.box<!L>
    }
    default(%d0: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = idr.call @build(%m) : (i64) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%n : i64, %t : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @map(%l: !idr.box<!L>) -> !idr.box<!L> {
    %r = idr.match %l : !idr.box<!L> -> (!idr.box<!L>) {
    case @N() {
      %e = idr.constant !idr.box<!L> #idr.con<!L, @N, []>
      idr.yield %e : !idr.box<!L>
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %h2 = arith.muli %h, %h : i64
      %t2 = idr.call @map(%t) : (!idr.box<!L>) -> !idr.box<!L>
      %c = idr.con !idr.box<!L> @C(%h2 : i64, %t2 : !idr.box<!L>)
      idr.yield %c : !idr.box<!L>
    }
    }
    return %r : !idr.box<!L>
  }
  idr.func @sum(%l: !idr.box<!L>, %acc: i64) -> i64 {
    %r = idr.match %l : !idr.box<!L> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      %a = arith.addi %acc, %h : i64
      %s = idr.call @sum(%t, %a) : (!idr.box<!L>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @head(%l: !idr.box<!L>) -> i64 {
    %r = idr.match %l : !idr.box<!L> -> (i64) {
    case @N() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @C(%h: i64, %t: !idr.box<!L>) {
      idr.yield %h : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %byte = arith.extui %c : i32 to i64
    %zero = arith.constant 0 : i64
    %c13 = arith.constant 13 : i64
    %c3 = arith.constant 3 : i64
    %ten = arith.remui %byte, %c13 : i64
    %three = arith.remui %byte, %c3 : i64
    %l = idr.call @build(%ten) : (i64) -> !idr.box<!L>
    %m = idr.call @map(%l) : (!idr.box<!L>) -> !idr.box<!L>
    %s1 = idr.call @sum(%m, %zero) : (!idr.box<!L>, i64) -> i64
    %m2 = idr.call @map(%m) : (!idr.box<!L>) -> !idr.box<!L>
    %s2 = idr.call @sum(%m2, %zero) : (!idr.box<!L>, i64) -> i64
    %h = idr.call @head(%m2) : (!idr.box<!L>) -> i64
    %k = idr.call @build(%three) : (i64) -> !idr.box<!L>
    %a = idr.call @map(%k) : (!idr.box<!L>) -> !idr.box<!L>
    %b = idr.call @sum(%k, %zero) : (!idr.box<!L>, i64) -> i64
    %ha = idr.call @head(%a) : (!idr.box<!L>) -> i64
    %w2 = idr.io.put_sint %s1, %w1 : i64
    %w3 = idr.io.put_sint %s2, %w2 : i64
    %w4 = idr.io.put_sint %h, %w3 : i64
    %w5 = idr.io.put_sint %b, %w4 : i64
    %w6 = idr.io.put_sint %ha, %w5 : i64
    return %w6 : !idr.world
  }
}
