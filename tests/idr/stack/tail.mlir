// RUN: idris-mlir-opt %s --idr-stack | FileCheck %s
// A call in tail position of a function on its caller's cycle of calls is
// a tail call (idr-tail-calls): the caller's frame is gone when the callee
// runs, so a cell the call takes is not on the stack (@even and @odd pass
// each other a fresh list). A call in tail position of a function off the
// cycle keeps the frame as any call does, and its cell stays on the stack
// (@helper, whose cell only @head reads).

// CHECK-LABEL: idr.func private @even(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func private @odd(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func private @helper(
// CHECK: con @Cons(%{{[^)]*}}) stack :
!List = !idr.data<"List", list [@Nil(), @Cons(i64, !idr.box<!idr.data<"List">>)]>
module {
  idr.func private @head(%l: !idr.box<!List>) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      idr.yield %h : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  idr.func private @even(%n: i64, %l: !idr.box<!List>) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %h = idr.call @head(%l) : (!idr.box<!List>) -> i64
      idr.yield %h : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %nil = idr.con @Nil() : () -> !idr.box<!List>
      %c = idr.con @Cons(%n, %nil) : (i64, !idr.box<!List>) -> !idr.box<!List>
      %x = idr.call @odd(%m, %c) : (i64, !idr.box<!List>) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func private @odd(%n: i64, %l: !idr.box<!List>) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %h = idr.call @head(%l) : (!idr.box<!List>) -> i64
      idr.yield %h : i64
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %nil = idr.con @Nil() : () -> !idr.box<!List>
      %c = idr.con @Cons(%n, %nil) : (i64, !idr.box<!List>) -> !idr.box<!List>
      %x = idr.call @even(%m, %c) : (i64, !idr.box<!List>) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func private @helper(%n: i64) -> i64 {
    %nil = idr.con @Nil() : () -> !idr.box<!List>
    %c = idr.con @Cons(%n, %nil) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %h = idr.call @head(%c) : (!idr.box<!List>) -> i64
    return %h : i64
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    %nil = idr.con @Nil() : () -> !idr.box<!List>
    %e = idr.call @even(%zero, %nil) : (i64, !idr.box<!List>) -> i64
    %h = idr.call @helper(%e) : (i64) -> i64
    return %h : i64
  }
}
