// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-stack,idr.func(idr-tail-loops)))' | FileCheck %s
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops),idr-stack))' | FileCheck %s
// A con in a loop writes the same stack slot on every iteration, so its
// cell must be dead when the iteration ends. idr-stack runs before
// idr-tail-loops makes self tail calls loops, and after it the marks are
// the same: a cell only read in its iteration is marked (@perIteration);
// one that the next iteration receives (@carried), or that leaves the loop
// as its result (@exits), is not. A call of the con's own function that is
// not in tail position runs a new frame with slots of its own, so passing
// the cell to it is like passing it to any call (@selfNonTail). A
// cell built before a loop may go round it and out of it, as long as it is
// only read (@outside); returned from the loop's result, it escapes
// (@outsideReturned).

// CHECK-LABEL: idr.func @perIteration(
// CHECK: scf.while
// CHECK: con {{.*}}@Cons({{[^)]*}}) stack
// CHECK-LABEL: idr.func @carried(
// CHECK: scf.while
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func @exits(
// CHECK: scf.while
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func @selfNonTail(
// CHECK: con {{.*}}@Cons({{[^)]*}}) stack
// CHECK-LABEL: idr.func @outside(
// CHECK: con {{.*}}@Cons({{[^)]*}}) stack
// CHECK: scf.while
// CHECK-LABEL: idr.func @outsideReturned(
// CHECK-NOT: ) stack :
// CHECK: return
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @loops root(@Prog.main) stage(first) {
  idr.func @sum(%l: !idr.box<!List>) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      %s = idr.call @sum(%t) : (!idr.box<!List>) -> i64
      %a = arith.addi %h, %s : i64
      idr.yield %a : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  // perIteration n acc = if n == 0 then acc
  //                      else perIteration (n - 1) (acc + sum [n])
  idr.func @perIteration(%n: i64, %acc: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %nil = idr.constant #idr.con<@Nil, []> : !idr.box<!List>
      %c = idr.con !idr.box<!List> @Cons(%n : i64, %nil : !idr.box<!List>)
      %s = idr.call @sum(%c) : (!idr.box<!List>) -> i64
      %a = arith.addi %acc, %s : i64
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %x = idr.call @perIteration(%m, %a) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // carried n l = if n == 0 then sum l else carried (n - 1) (n :: l)
  idr.func @carried(%n: i64, %l: !idr.box<!List>) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %s = idr.call @sum(%l) : (!idr.box<!List>) -> i64
      idr.yield %s : i64
    }
    default {
      %c = idr.con !idr.box<!List> @Cons(%n : i64, %l : !idr.box<!List>)
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %x = idr.call @carried(%m, %c) : (i64, !idr.box<!List>) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // exits n = if n == 0 then [n] else exits (n - 1)
  idr.func @exits(%n: i64) -> !idr.box<!List> attributes {total} {
    %r = idr.match_lit %n : i64 -> (!idr.box<!List>) {
    case 0 {
      %nil = idr.constant #idr.con<@Nil, []> : !idr.box<!List>
      %c = idr.con !idr.box<!List> @Cons(%n : i64, %nil : !idr.box<!List>)
      idr.yield %c : !idr.box<!List>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %x = idr.call @exits(%m) : (i64) -> !idr.box<!List>
      idr.yield %x : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  // selfNonTail n l = if n == 0 then sum l else 1 + selfNonTail (n - 1) (n :: l)
  idr.func @selfNonTail(%n: i64, %l: !idr.box<!List>) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %s = idr.call @sum(%l) : (!idr.box<!List>) -> i64
      idr.yield %s : i64
    }
    default {
      %c = idr.con !idr.box<!List> @Cons(%n : i64, %l : !idr.box<!List>)
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %x = idr.call @selfNonTail(%m, %c) : (i64, !idr.box<!List>) -> i64
      %y = arith.addi %x, %one : i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @outside(%n: i64, %t: !idr.box<!List>) -> i64 {
    %c = idr.con !idr.box<!List> @Cons(%n : i64, %t : !idr.box<!List>)
    %r:2 = scf.while (%i = %n, %l = %c) : (i64, !idr.box<!List>) -> (i64, !idr.box<!List>) {
      %zero = arith.constant 0 : i64
      %more = arith.cmpi ne, %i, %zero : i64
      scf.condition(%more) %i, %l : i64, !idr.box<!List>
    } do {
    ^bb0(%j: i64, %k: !idr.box<!List>):
      %one = arith.constant 1 : i64
      %m = arith.subi %j, %one : i64
      scf.yield %m, %k : i64, !idr.box<!List>
    }
    %s = idr.call @sum(%r#1) : (!idr.box<!List>) -> i64
    return %s : i64
  }
  idr.func @outsideReturned(%n: i64, %t: !idr.box<!List>) -> !idr.box<!List> {
    %c = idr.con !idr.box<!List> @Cons(%n : i64, %t : !idr.box<!List>)
    %r:2 = scf.while (%i = %n, %l = %c) : (i64, !idr.box<!List>) -> (i64, !idr.box<!List>) {
      %zero = arith.constant 0 : i64
      %more = arith.cmpi ne, %i, %zero : i64
      scf.condition(%more) %i, %l : i64, !idr.box<!List>
    } do {
    ^bb0(%j: i64, %k: !idr.box<!List>):
      %one = arith.constant 1 : i64
      %m = arith.subi %j, %one : i64
      scf.yield %m, %k : i64, !idr.box<!List>
    }
    return %r#1 : !idr.box<!List>
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
