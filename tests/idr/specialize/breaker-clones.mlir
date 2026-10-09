// RUN: idris-mlir-opt %s -split-input-file --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// A clone runs its callee's loop, so it breaks the loop where its callee
// does: a clone of a loop breaker keeps no_inline. A call of the breaker in
// the clone may become a call of the clone only in a later round, once
// inlining shows what consumes it; until then the clone is on no cycle of
// references, and inlining it would put that call back into its caller,
// for which specialization makes the clone again. A clone that unrolls a
// decreasing parameter, or that refers to no function, breaks no loop.

// @loop recurses through a closure of @again, which calls @loop back with
// the pair it captured: the pair is fixed, and @loop breaks the cycle. Its
// clone for a pair built here keeps the mark; the clone of @again, which
// breaks nothing, has none.
// CHECK-LABEL: func.func private @use(
// CHECK: call @[[LOOP:loop\$spec\$[0-9]+]](
// CHECK: func.func private @[[LOOP]](
// CHECK-SAME: no_inline
// CHECK: func.func private @again$spec$
// CHECK-NOT: no_inline
// CHECK: return
module attributes {idr.program} {
  idr.data @P box {
    idr.ctor @MkP (i64, i64)
  }
  func.func private @loop(%p: !idr.box<@P>, %n: i64) -> i64 attributes {no_inline} {
    %f = idr.closure @again(%p) : (!idr.box<@P>) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  func.func private @again(%p: !idr.box<@P>, %n: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %z = arith.cmpi eq, %n, %c0 : i64
    %b = arith.extui %z : i1 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 1 {
      %a = idr.field %p[@MkP, 0] : !idr.box<@P> -> i64
      idr.yield %a : i64
    }
    default {
      %m = arith.subi %n, %c1 : i64
      %x = func.call @loop(%p, %m) : (!idr.box<@P>, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @use(%a: i64, %b: i64, %n: i64) -> i64 {
    %p = idr.con @P::@MkP(%a, %b) : (i64, i64) -> !idr.box<@P>
    %r = func.call @loop(%p, %n) : (!idr.box<@P>, i64) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// @sum takes its list apart, one cell a step: the list decreases. Its
// clones for a list of one cell and for the empty list unroll it, and break
// no loop.
// CHECK-LABEL: func.func private @use(
// CHECK: call @[[ONE:sum\$spec\$[0-9]+]](
// CHECK: func.func private @[[ONE]](
// CHECK-NOT: no_inline
// CHECK: call @[[NIL:sum\$spec\$[0-9]+]](
// CHECK: func.func private @[[NIL]](
// CHECK-NOT: no_inline
// CHECK: return
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@L>)
  }
  func.func private @sum(%xs: !idr.box<@L>, %acc: i64) -> i64 attributes {no_inline} {
    %r = idr.match %xs : !idr.box<@L> -> (i64) {
    case @Nil() {
      idr.yield %acc : i64
    }
    case @Cons(%h: i64, %t: !idr.box<@L>) {
      %a = arith.addi %acc, %h : i64
      %x = func.call @sum(%t, %a) : (!idr.box<@L>, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @use(%h: i64, %acc: i64) -> i64 {
    %nil = idr.con @L::@Nil() : () -> !idr.box<@L>
    %xs = idr.con @L::@Cons(%h, %nil) : (i64, !idr.box<@L>) -> !idr.box<@L>
    %r = func.call @sum(%xs, %acc) : (!idr.box<@L>, i64) -> i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}

// -----

// @run passes its mode on unchanged: it is fixed. In mode @Once the clone
// returns without a call, and refers to no function: no breaker. In mode
// @Again it calls itself, and keeps the mark.
// CHECK-LABEL: func.func private @use(
// CHECK: call @[[ONCE:run\$spec\$[0-9]+]](
// CHECK: call @[[AGAIN:run\$spec\$[0-9]+]](
// CHECK: func.func private @[[ONCE]](
// CHECK-NOT: no_inline
// CHECK: return
// CHECK: func.func private @[[AGAIN]](
// CHECK-SAME: no_inline
module attributes {idr.program} {
  idr.data @Mode box {
    idr.ctor @Once ()
    idr.ctor @Again ()
  }
  func.func private @run(%mode: !idr.box<@Mode>, %n: i64) -> i64 attributes {no_inline} {
    %r = idr.match %mode : !idr.box<@Mode> -> (i64) {
    case @Once() {
      %c1 = arith.constant 1 : i64
      %s = arith.addi %n, %c1 : i64
      idr.yield %s : i64
    }
    case @Again() {
      %c2 = arith.constant 2 : i64
      %d = arith.muli %n, %c2 : i64
      %x = func.call @run(%mode, %d) : (!idr.box<@Mode>, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  func.func private @use(%n: i64) -> i64 {
    %once = idr.con @Mode::@Once() : () -> !idr.box<@Mode>
    %again = idr.con @Mode::@Again() : () -> !idr.box<@Mode>
    %a = func.call @run(%once, %n) : (!idr.box<@Mode>, i64) -> i64
    %b = func.call @run(%again, %n) : (!idr.box<@Mode>, i64) -> i64
    %r = arith.addi %a, %b : i64
    return %r : i64
  }
  func.func @Main.main() -> i64 {
    %c = arith.constant 0 : i64
    return %c : i64
  }
}
