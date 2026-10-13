// RUN: idris-mlir-opt %s --idr-specialize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-specialize > %t2.mlir
// RUN: diff %t.mlir %t2.mlir
// RUN: idris-mlir-opt %s --idr-specialize --symbol-dce --idr-expect=holds=one-clone=@map -o /dev/null
// A closure passed to a recursive map, whose function is a fixed
// parameter. Its label is static and its capture a runtime leaf: the clone
// of @map rebuilds the closure over a new parameter, and the recursive call,
// which passes the same closure, has the clone's key and calls the clone
// itself: one clone serves the whole recursion. A second run changes
// nothing.
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@L>)
  }
  idr.func private @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  // CHECK-LABEL: idr.func private @map(
  // CHECK: call @map(
  idr.func private @map(%f: !idr.fn<(i64) -> (i64)>, %xs: !idr.box<@L>) -> !idr.box<@L> attributes {total} {
    %r = idr.match %xs : !idr.box<@L> -> (!idr.box<@L>) {
    case @Nil() {
      %n = idr.con @L::@Nil() : () -> !idr.box<@L>
      idr.yield %n : !idr.box<@L>
    }
    case @Cons(%h: i64, %t: !idr.box<@L>) {
      %h2 = idr.apply %f(%h) : !idr.fn<(i64) -> (i64)>
      %t2 = idr.call @map(%f, %t) : (!idr.fn<(i64) -> (i64)>, !idr.box<@L>) -> !idr.box<@L>
      %c = idr.con @L::@Cons(%h2, %t2) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  // CHECK-LABEL: idr.func private @use(
  // CHECK-SAME: %[[N:.*]]: i64, %[[XS:.*]]: !L)
  // CHECK: %[[R:.*]] = call @[[M:map\.spec[0-9]+]](%[[N]], %[[XS]])
  // CHECK-NEXT: return %[[R]]
  idr.func private @use(%n: i64, %xs: !idr.box<@L>) -> !idr.box<@L> attributes {total} {
    %f = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.call @map(%f, %xs) : (!idr.fn<(i64) -> (i64)>, !idr.box<@L>) -> !idr.box<@L>
    return %r : !idr.box<@L>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %xs = idr.call @read(%n) : (i64) -> !idr.box<@L>
    %r = idr.call @use(%n, %xs) : (i64, !idr.box<@L>) -> !idr.box<@L>
    %s = idr.call @first(%r) : (!idr.box<@L>) -> i64
    %w2 = idr.io.put_int signed %s, %w1 : i64
    return %w2 : !idr.world
  }
  // A list known only at runtime.
  idr.func private @read(%n: i64) -> !idr.box<@L> attributes {total, no_inline} {
    %nil = idr.con @L::@Nil() : () -> !idr.box<@L>
    %xs = idr.con @L::@Cons(%n, %nil) : (i64, !idr.box<@L>) -> !idr.box<@L>
    return %xs : !idr.box<@L>
  }
  idr.func private @first(%xs: !idr.box<@L>) -> i64 attributes {total} {
    %r = idr.match %xs : !idr.box<@L> -> (i64) {
    case @Nil() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @Cons(%h: i64, %t: !idr.box<@L>) {
      idr.yield %h : i64
    }
    }
    return %r : i64
  }
  // CHECK: idr.func private @[[M]](
  // CHECK-SAME: %[[A:[a-z0-9_]+]]: i64, %[[L:[a-z0-9_]+]]: !L
  // CHECK-SAME: total
  // CHECK: case @Cons(%[[H:.*]]: i64, %[[T:.*]]: !L)
  // CHECK: call @add(%[[A]], %[[H]])
  // CHECK-NEXT: call @[[M]](%[[A]], %[[T]])
  // CHECK-NOT: idr.func private @map.spec
}
