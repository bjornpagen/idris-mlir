// RUN: idris-mlir-opt %s --idr-stack | FileCheck %s
// A cell stored in a constructor, boxed or not, goes wherever that value
// goes and wherever what is read from it goes. So it may stay on the stack
// when the value holding it does and nothing read from it escapes: a local
// list read by @head (@nested), a pair read for its number (@unboxedRead).
// It escapes with the value holding it (@storedReturned, @unboxedReturned),
// or when what is read from that value does: @tail returns the tail it
// reads (@nestedTail), and the outer cell of @nestedTail still stays. A cell
// among a closure's captures, or passed to an unknown closure, escapes.

// CHECK-LABEL: func.func private @nested(
// CHECK: idr.con @List::@Cons(%{{[^)]*}}) {idr.stack} :
// CHECK-NEXT: idr.con @List::@Cons(%{{[^)]*}}) {idr.stack} :
// CHECK-LABEL: func.func private @nestedTail(
// CHECK: idr.con @List::@Cons(%{{[^)]*}}) :
// CHECK-NEXT: idr.con @List::@Cons(%{{[^)]*}}) {idr.stack} :
// CHECK-LABEL: func.func private @storedReturned(
// CHECK-NOT: idr.stack
// CHECK: return
// CHECK-LABEL: func.func private @unboxedRead(
// CHECK: idr.con @List::@Cons(%{{[^)]*}}) {idr.stack} :
// CHECK-LABEL: func.func private @unboxedReturned(
// CHECK-NOT: idr.stack
// CHECK: return
// CHECK-LABEL: func.func private @captured(
// CHECK-NOT: idr.stack
// CHECK: return
// CHECK-LABEL: func.func private @applied(
// CHECK-NOT: idr.stack
// CHECK: return
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  idr.data @Pair {
    idr.ctor @MkPair (!idr.box<@List>, i64)
  }
  func.func private @head(%l: !idr.box<@List>) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      idr.yield %h : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  func.func private @tail(%l: !idr.box<@List>) -> !idr.box<@List> {
    %r = idr.match %l : !idr.box<@List> -> (!idr.box<@List>) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      idr.yield %t : !idr.box<@List>
    }
    default {
      %nil = idr.constant #idr.con<@List::@Nil, []> : !idr.box<@List>
      idr.yield %nil : !idr.box<@List>
    }
    }
    return %r : !idr.box<@List>
  }
  func.func private @plusHead(%l: !idr.box<@List>, %y: i64) -> i64 {
    %h = func.call @head(%l) : (!idr.box<@List>) -> i64
    %r = arith.addi %h, %y : i64
    return %r : i64
  }
  func.func private @nested(%x: i64, %t: !idr.box<@List>) -> i64 {
    %inner = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %outer = idr.con @List::@Cons(%x, %inner) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %r = func.call @head(%outer) : (!idr.box<@List>) -> i64
    return %r : i64
  }
  func.func private @nestedTail(%x: i64, %t: !idr.box<@List>) -> !idr.box<@List> {
    %inner = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %outer = idr.con @List::@Cons(%x, %inner) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %r = func.call @tail(%outer) : (!idr.box<@List>) -> !idr.box<@List>
    return %r : !idr.box<@List>
  }
  func.func private @storedReturned(%x: i64, %t: !idr.box<@List>) -> !idr.box<@List> {
    %inner = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %outer = idr.con @List::@Cons(%x, %inner) : (i64, !idr.box<@List>) -> !idr.box<@List>
    return %outer : !idr.box<@List>
  }
  func.func private @unboxedRead(%x: i64, %t: !idr.box<@List>) -> i64 {
    %c = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %p = idr.con @Pair::@MkPair(%c, %x) : (!idr.box<@List>, i64) -> !idr.data<@Pair>
    %y = idr.field %p[@MkPair, 1] : !idr.data<@Pair> -> i64
    return %y : i64
  }
  func.func private @unboxedReturned(%x: i64, %t: !idr.box<@List>) -> !idr.data<@Pair> {
    %c = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %p = idr.con @Pair::@MkPair(%c, %x) : (!idr.box<@List>, i64) -> !idr.data<@Pair>
    return %p : !idr.data<@Pair>
  }
  func.func private @captured(%x: i64, %t: !idr.box<@List>) -> i64 {
    %c = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %f = idr.closure @plusHead(%c) : (!idr.box<@List>) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func private @applied(%f: !idr.fn<(!idr.box<@List>) -> (i64)>, %x: i64,
                             %t: !idr.box<@List>) -> i64 {
    %c = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %r = idr.apply %f(%c) : !idr.fn<(!idr.box<@List>) -> (i64)>
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
