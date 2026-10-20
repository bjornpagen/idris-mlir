// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-cells)))' -o %t.none.mlir
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-cells),idr-rc-stack))' --mlir-disable-threading -mlir-debug-counter=idr-stack-cell-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-rc-cells),idr-rc-stack))' -o %t.done.mlir
// RUN: %status 1 diff %t.none.mlir %t.done.mlir
// RUN: %differential %s %t.done.mlir
// With every action skipped the pass is the identity, and with none it
// changes the module. The root runs every function on the byte it reads,
// and the program prints with the cells on the stack what it printed with
// them on the heap, on every byte.
!Big = !idr.data<"Big">
!Huge = !idr.data<"Huge">
!List = !idr.data<"List">
#types = #idr.types<
  "Big" = plain [@Big(i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)],
  "Huge" = plain [@Huge(i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)],
  "List" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]
>
idr.program @budget root(@Prog.main) stage(first) types #types {
  idr.func @firstBig(%b: !idr.box<!Big>) -> i64 {
    %x = idr.field %b : !idr.box<!Big> @Big[0] -> i64
    return %x : i64
  }
  idr.func @firstHuge(%b: !idr.box<!Huge>) -> i64 {
    %x = idr.field %b : !idr.box<!Huge> @Huge[0] -> i64
    return %x : i64
  }
  idr.func @largest(%a: i64) -> i64 {
    %b = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %x = idr.call @firstBig(%b) : (!idr.box<!Big>) -> i64
    return %x : i64
  }
  idr.func @large(%a: i64) -> i64 {
    %b = idr.con !idr.box<!Huge> @Huge(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %x = idr.call @firstHuge(%b) : (!idr.box<!Huge>) -> i64
    return %x : i64
  }
  idr.func @frame(%a: i64) -> i64 {
    %b0 = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %b1 = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %b2 = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %b3 = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %b4 = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %x0 = idr.call @firstBig(%b0) : (!idr.box<!Big>) -> i64
    %x1 = idr.call @firstBig(%b1) : (!idr.box<!Big>) -> i64
    %x2 = idr.call @firstBig(%b2) : (!idr.box<!Big>) -> i64
    %x3 = idr.call @firstBig(%b3) : (!idr.box<!Big>) -> i64
    %x4 = idr.call @firstBig(%b4) : (!idr.box<!Big>) -> i64
    %s1 = arith.addi %x0, %x1 : i64
    %s2 = arith.addi %s1, %x2 : i64
    %s3 = arith.addi %s2, %x3 : i64
    %s4 = arith.addi %s3, %x4 : i64
    return %s4 : i64
  }
  idr.func @recursive(%a: i64, %t: !idr.box<!List>) -> i64 {
    %c0 = idr.con !idr.box<!List> @Cons(%a : i64, %t : !idr.box<!List>)
    %c1 = idr.con !idr.box<!List> @Cons(%a : i64, %t : !idr.box<!List>)
    %c2 = idr.con !idr.box<!List> @Cons(%a : i64, %t : !idr.box<!List>)
    %r = idr.match_lit %a : i64 -> (i64) {
    case 0 {
      idr.yield %a : i64
    }
    default(%d0: i64) {
      %x0 = idr.call @head(%c0) : (!idr.box<!List>) -> i64
      %x1 = idr.call @head(%c1) : (!idr.box<!List>) -> i64
      %x2 = idr.call @head(%c2) : (!idr.box<!List>) -> i64
      %one = arith.constant 1 : i64
      %m = arith.subi %a, %one : i64
      %rest = idr.call @recursive(%m, %t) : (i64, !idr.box<!List>) -> i64
      %s1 = arith.addi %x0, %x1 : i64
      %s2 = arith.addi %s1, %x2 : i64
      %s3 = arith.addi %s2, %rest : i64
      idr.yield %s3 : i64
    }
    }
    return %r : i64
  }
  idr.func @head(%l: !idr.box<!List>) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      idr.yield %h : i64
    }
    default(%d1: !idr.box<!List>) {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  // The program's root runs every function above on the byte it reads,
  // @recursive on the byte modulo 16 and a list of one cell.
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %a = arith.extui %ch : i32 to i64
    %x0 = idr.call @largest(%a) : (i64) -> i64
    %w1 = idr.io.put_sint %x0, %w0 : i64
    %x1 = idr.call @large(%a) : (i64) -> i64
    %w2 = idr.io.put_sint %x1, %w1 : i64
    %x2 = idr.call @frame(%a) : (i64) -> i64
    %w3 = idr.io.put_sint %x2, %w2 : i64
    %c15 = arith.constant 15 : i64
    %k = arith.andi %a, %c15 : i64
    %nil = idr.con !idr.box<!List> @Nil()
    %c9 = arith.constant 9 : i64
    %t = idr.con !idr.box<!List> @Cons(%c9 : i64, %nil : !idr.box<!List>)
    %x3 = idr.call @recursive(%k, %t) : (i64, !idr.box<!List>) -> i64
    %w4 = idr.io.put_sint %x3, %w3 : i64
    return %w4 : !idr.world
  }
}
