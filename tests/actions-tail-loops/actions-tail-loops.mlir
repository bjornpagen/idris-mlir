// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-rc))' -o %t.in.mlir
// RUN: idris-mlir-opt %t.in.mlir -o %t.none.mlir
// RUN: idris-mlir-opt %t.in.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)))' --mlir-disable-threading -mlir-debug-counter=idr-tail-loops-loop-count=0,idr-tail-loops-hoist-count=0,idr-tail-loops-uplift-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %t.in.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)))' -o %t.done.mlir
// RUN: %status 1 diff %t.none.mlir %t.done.mlir
// RUN: %differential %t.in.mlir %t.done.mlir
// STDIN:
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0017
// STDIN: \0020
// STDIN: \0177
// STDIN: \0200
// STDIN: \0377
// With every action skipped the pass is the identity, and with none it
// changes the module. The root runs every function on the byte it reads,
// and the counted program prints with its loops what it printed before,
// on each of the inputs the STDIN lines name: 0, 1, 2, 15, 16, 127, 128
// and 255, and the end of input.
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @"tail-loop" root(@Main.main) stage(first) {
  idr.func @count(%acc: i64, %n: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d0: i64) {
      %c1 = arith.constant 1 : i64
      %a = arith.addi %acc, %c1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = idr.call @count(%a, %m) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @upto(%i: i64, %n: i64, %acc: i64) -> i64 attributes {total} {
    %lt = arith.cmpi slt, %i, %n : i64
    %b = arith.extui %lt : i1 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default(%d1: i64) {
      %c1 = arith.constant 1 : i64
      %j = arith.addi %i, %c1 : i64
      %sq = arith.muli %i, %i : i64
      %a = arith.addi %acc, %sq : i64
      %x = idr.call @upto(%j, %n, %a) : (i64, i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @until(%i: i64, %n: i64) -> i64 attributes {total} {
    %lt = arith.cmpi slt, %i, %n : i64
    %b = arith.extui %lt : i1 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      idr.yield %i : i64
    }
    default(%d2: i64) {
      %c3 = arith.constant 3 : i64
      %j = arith.addi %i, %c3 : i64
      %x = idr.call @until(%j, %n) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @spin(%x: i64) -> i64 {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    %r = idr.call @spin(%y) : (i64) -> i64
    return %r : i64
  }
  idr.func @sum(%acc: i64, %xs: !idr.box<!List>) -> i64 attributes {total} {
    %r = idr.match %xs : !idr.box<!List> -> (i64) {
    case @Nil() {
      idr.yield %acc : i64
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %a = arith.addi %acc, %x : i64
      %s = idr.call @sum(%a, %rest) : (i64, !idr.box<!List>) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @echo(%n: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %w1 = idr.io.put_sint %n, %w : i64
    %r = idr.match_lit %n : i64 -> (!idr.world) {
    case 0 {
      idr.yield %w1 : !idr.world
    }
    default(%d3: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = idr.call @echo(%m, %w1) : (i64, !idr.world) -> !idr.world
      idr.yield %x : !idr.world
    }
    }
    return %r : !idr.world
  }
  idr.func @fib(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    case 1 {
      idr.yield %n : i64
    }
    default(%d4: i64) {
      %c1 = arith.constant 1 : i64
      %c2 = arith.constant 2 : i64
      %a = arith.subi %n, %c1 : i64
      %b = arith.subi %n, %c2 : i64
      %x = idr.call @fib(%a) : (i64) -> i64
      %y = idr.call @fib(%b) : (i64) -> i64
      %s = arith.addi %x, %y : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  // The program's root runs every function above on the byte it reads:
  // @echo and @fib on it modulo 16, and @spin, which never returns, only
  // on the byte 200, which no input of the differential is.
  idr.func @Main.main(%w0: !idr.world) -> !idr.world {
    %ch, %w = idr.io.get_byte %w0
    %n = arith.extui %ch : i32 to i64
    %c15 = arith.constant 15 : i64
    %k = arith.andi %n, %c15 : i64
    %nil = idr.con !idr.box<!List> @Nil()
    %c7 = arith.constant 7 : i64
    %xs1 = idr.con !idr.box<!List> @Cons(%c7 : i64, %nil : !idr.box<!List>)
    %xs = idr.con !idr.box<!List> @Cons(%n : i64, %xs1 : !idr.box<!List>)
    %c0 = arith.constant 0 : i64
    %a = idr.call @count(%c0, %n) : (i64, i64) -> i64
    %u = idr.call @upto(%c0, %n, %c0) : (i64, i64, i64) -> i64
    %v = idr.call @until(%c0, %n) : (i64, i64) -> i64
    %b = idr.match_lit %n : i64 -> (i64) {
    case 200 {
      %y = idr.call @spin(%c0) : (i64) -> i64
      idr.yield %y : i64
    }
    default(%d5: i64) {
      idr.yield %c0 : i64
    }
    }
    %s = idr.call @sum(%c0, %xs) : (i64, !idr.box<!List>) -> i64
    %w1 = idr.call @echo(%k, %w) : (i64, !idr.world) -> !idr.world
    %c = idr.call @fib(%k) : (i64) -> i64
    %w2 = idr.io.put_sint %u, %w1 : i64
    %w3 = idr.io.put_sint %s, %w2 : i64
    %w4 = idr.io.put_sint %c, %w3 : i64
    %w5 = idr.io.put_sint %a, %w4 : i64
    %w6 = idr.io.put_sint %v, %w5 : i64
    %w7 = idr.io.put_sint %b, %w6 : i64
    return %w7 : !idr.world
  }
}
