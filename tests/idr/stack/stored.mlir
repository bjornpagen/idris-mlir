// RUN: idris-mlir-opt %s --idr-stack | FileCheck %s
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// A cell stored in a constructor, boxed or not, goes wherever that value
// goes and wherever what is read from it goes. So it may stay on the stack
// when the value holding it does and nothing read from it escapes: a local
// list read by @head (@nested), a pair read for its number (@unboxedRead).
// It escapes with the value holding it (@storedReturned, @unboxedReturned),
// or when what is read from that value does: @tail returns the tail it
// reads (@nestedTail), and the outer cell of @nestedTail still stays. A cell
// among a closure's captures, or passed to an unknown closure, escapes.

// CHECK-LABEL: idr.func @nested(
// CHECK: con {{.*}}@Cons({{[^)]*}}) stack
// CHECK-NEXT: con {{.*}}@Cons({{[^)]*}}) stack
// CHECK-LABEL: idr.func @nestedTail(
// CHECK: con {{.*}}@Cons({{[^)]*}}){{$}}
// CHECK-NEXT: con {{.*}}@Cons({{[^)]*}}) stack
// CHECK-LABEL: idr.func @storedReturned(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func @unboxedRead(
// CHECK: con {{.*}}@Cons({{[^)]*}}) stack
// CHECK-LABEL: idr.func @unboxedReturned(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func @captured(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func @applied(
// CHECK-NOT: ) stack :
// CHECK: return
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
!Pair = !idr.data<"Pair", plain [@MkPair(!idr.box<!List>, i64)]>
idr.program @stored root(@Prog.main) stage(higher) {
  idr.func @head(%l: !idr.box<!List>) -> i64 {
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
  idr.func @tail(%l: !idr.box<!List>) -> !idr.box<!List> {
    %r = idr.match %l : !idr.box<!List> -> (!idr.box<!List>) {
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      idr.yield %t : !idr.box<!List>
    }
    default {
      %nil = idr.constant #idr.con<!List, @Nil, []> : !idr.box<!List>
      idr.yield %nil : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  idr.func @plusHead(%l: !idr.box<!List>, %y: i64) -> i64 {
    %h = idr.call @head(%l) : (!idr.box<!List>) -> i64
    %r = arith.addi %h, %y : i64
    return %r : i64
  }
  idr.func @nested(%x: i64, %t: !idr.box<!List>) -> i64 {
    %inner = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
    %outer = idr.con !idr.box<!List> @Cons(%x : i64, %inner : !idr.box<!List>)
    %r = idr.call @head(%outer) : (!idr.box<!List>) -> i64
    return %r : i64
  }
  idr.func @nestedTail(%x: i64, %t: !idr.box<!List>) -> !idr.box<!List> {
    %inner = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
    %outer = idr.con !idr.box<!List> @Cons(%x : i64, %inner : !idr.box<!List>)
    %r = idr.call @tail(%outer) : (!idr.box<!List>) -> !idr.box<!List>
    return %r : !idr.box<!List>
  }
  idr.func @storedReturned(%x: i64, %t: !idr.box<!List>) -> !idr.box<!List> {
    %inner = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
    %outer = idr.con !idr.box<!List> @Cons(%x : i64, %inner : !idr.box<!List>)
    return %outer : !idr.box<!List>
  }
  idr.func @unboxedRead(%x: i64, %t: !idr.box<!List>) -> i64 {
    %c = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
    %p = idr.con !Pair @MkPair(%c : !idr.box<!List>, %x : i64)
    %y = idr.field %p : !Pair @MkPair[1] -> i64
    return %y : i64
  }
  idr.func @unboxedReturned(%x: i64, %t: !idr.box<!List>) -> !Pair {
    %c = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
    %p = idr.con !Pair @MkPair(%c : !idr.box<!List>, %x : i64)
    return %p : !Pair
  }
  idr.func @captured(%x: i64, %t: !idr.box<!List>) -> i64 {
    %c = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
    %f = idr.closure @plusHead(%c) : (!idr.box<!List>) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @applied(%f: !idr.fn<(!idr.box<!List>) -> (i64)>, %x: i64,
                             %t: !idr.box<!List>) -> i64 {
    %c = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
    %r = idr.apply %f(%c) : !idr.fn<(!idr.box<!List>) -> (i64)>
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
