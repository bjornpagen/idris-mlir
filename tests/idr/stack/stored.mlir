// RUN: idris-mlir-opt %s --idr-stack | FileCheck %s
// A cell stored in a constructor, boxed or not, goes wherever that value
// goes and wherever what is read from it goes. So it may stay on the stack
// when the value holding it does and nothing read from it escapes: a local
// list read by @head (@nested), a pair read for its number (@unboxedRead).
// It escapes with the value holding it (@storedReturned, @unboxedReturned),
// or when what is read from that value does: @tail returns the tail it
// reads (@nestedTail), and the outer cell of @nestedTail still stays. A cell
// among a closure's captures, or passed to an unknown closure, escapes.

// CHECK-LABEL: idr.func private @nested(
// CHECK: con @Cons(%{{[^)]*}}) stack :
// CHECK-NEXT: con @Cons(%{{[^)]*}}) stack :
// CHECK-LABEL: idr.func private @nestedTail(
// CHECK: con @Cons(%{{[^)]*}}) :
// CHECK-NEXT: con @Cons(%{{[^)]*}}) stack :
// CHECK-LABEL: idr.func private @storedReturned(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func private @unboxedRead(
// CHECK: con @Cons(%{{[^)]*}}) stack :
// CHECK-LABEL: idr.func private @unboxedReturned(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func private @captured(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func private @applied(
// CHECK-NOT: ) stack :
// CHECK: return
!List = !idr.data<"List", list [@Nil(), @Cons(i64, !idr.box<!idr.data<"List">>)]>
!Pair = !idr.data<"Pair", plain [@MkPair(!idr.box<!List>, i64)]>
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
  idr.func private @tail(%l: !idr.box<!List>) -> !idr.box<!List> {
    %r = idr.match %l : !idr.box<!List> -> (!idr.box<!List>) {
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      idr.yield %t : !idr.box<!List>
    }
    default {
      %nil = idr.constant #idr.con<@Nil, []> : !idr.box<!List>
      idr.yield %nil : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  idr.func private @plusHead(%l: !idr.box<!List>, %y: i64) -> i64 {
    %h = idr.call @head(%l) : (!idr.box<!List>) -> i64
    %r = arith.addi %h, %y : i64
    return %r : i64
  }
  idr.func private @nested(%x: i64, %t: !idr.box<!List>) -> i64 {
    %inner = idr.con @Cons(%x, %t) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %outer = idr.con @Cons(%x, %inner) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %r = idr.call @head(%outer) : (!idr.box<!List>) -> i64
    return %r : i64
  }
  idr.func private @nestedTail(%x: i64, %t: !idr.box<!List>) -> !idr.box<!List> {
    %inner = idr.con @Cons(%x, %t) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %outer = idr.con @Cons(%x, %inner) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %r = idr.call @tail(%outer) : (!idr.box<!List>) -> !idr.box<!List>
    return %r : !idr.box<!List>
  }
  idr.func private @storedReturned(%x: i64, %t: !idr.box<!List>) -> !idr.box<!List> {
    %inner = idr.con @Cons(%x, %t) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %outer = idr.con @Cons(%x, %inner) : (i64, !idr.box<!List>) -> !idr.box<!List>
    return %outer : !idr.box<!List>
  }
  idr.func private @unboxedRead(%x: i64, %t: !idr.box<!List>) -> i64 {
    %c = idr.con @Cons(%x, %t) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %p = idr.con @MkPair(%c, %x) : (!idr.box<!List>, i64) -> !Pair
    %y = idr.field %p[@MkPair, 1] : !Pair -> i64
    return %y : i64
  }
  idr.func private @unboxedReturned(%x: i64, %t: !idr.box<!List>) -> !Pair {
    %c = idr.con @Cons(%x, %t) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %p = idr.con @MkPair(%c, %x) : (!idr.box<!List>, i64) -> !Pair
    return %p : !Pair
  }
  idr.func private @captured(%x: i64, %t: !idr.box<!List>) -> i64 {
    %c = idr.con @Cons(%x, %t) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %f = idr.closure @plusHead(%c) : (!idr.box<!List>) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func private @applied(%f: !idr.fn<(!idr.box<!List>) -> (i64)>, %x: i64,
                             %t: !idr.box<!List>) -> i64 {
    %c = idr.con @Cons(%x, %t) : (i64, !idr.box<!List>) -> !idr.box<!List>
    %r = idr.apply %f(%c) : !idr.fn<(!idr.box<!List>) -> (i64)>
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
