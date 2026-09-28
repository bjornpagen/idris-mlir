// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: %status 1 idris-mlir-opt %s --idr-defunctionalize --idr-check-profile -o %t.out 2> %t.err
// RUN: FileCheck %s --check-prefix=ERR < %t.err
// Closures that a recursion on a runtime value makes larger: each level
// captures a closure of its own type, so no finite sum over labels stands
// for them, and the types stay closures. The unrelated closure type in the
// same module is still converted. idr-check-profile reports the first
// closure built at runtime (growing-lazy.mlir has the Lazy one alone).
// CHECK: idr.data @[[F0:fn\$[0-9]+]] {
// CHECK-NEXT: idr.ctor @Main.neg tag 0 ()
// CHECK-NOT: idr.data @fn$
// CHECK-LABEL: func.func private @Main.pick(
// CHECK-SAME: -> !idr.fn<(i64) -> (i64)>
// CHECK: idr.closure @Main.inc()
// CHECK: idr.closure @Main.twice(%{{.*}}) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
// CHECK-LABEL: func.func private @Main.later(
// CHECK-SAME: -> !idr.fn<() -> (i64)>
// CHECK-LABEL: func.func @Main.main(
// CHECK: idr.apply %{{.*}}(%{{.*}}) : !idr.fn<(i64) -> (i64)>
// CHECK: idr.match %{{.*}} : !idr.data<@[[F0]]> -> (i1)
// ERR: Main.idr:16:5: error: unsupported (PROF-HEAP-1){{.*}}@Main.twice
// ERR-NOT: error
module attributes {idr.program} {
  func.func private @Main.inc(%x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    return %y : i64
  }
  func.func private @Main.twice(%f: !idr.fn<(i64) -> (i64)> {idr.quantity = "w"}, %x: i64 {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %y = idr.apply %f(%x) : !idr.fn<(i64) -> (i64)>
    %z = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
    return %z : i64
  }
  func.func private @Main.neg(%b: i1 {idr.quantity = "w"}) -> i1 attributes {idr.total} {
    %t = arith.constant true
    %r = arith.xori %b, %t : i1
    return %r : i1
  }
  func.func private @Main.force(%l: !idr.fn<() -> (i64)> {idr.quantity = "w"}) -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    %v = idr.apply %l() : !idr.fn<() -> (i64)>
    %r = arith.addi %v, %c1 : i64
    return %r : i64
  }
  // pick 0 = inc; pick n = twice (pick (n - 1))
  func.func private @Main.pick(%n: i64 {idr.quantity = "w"}) -> !idr.fn<(i64) -> (i64)> {
    %r = idr.match_lit %n : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %f = idr.closure @Main.inc() : () -> !idr.fn<(i64) -> (i64)>
      idr.yield %f : !idr.fn<(i64) -> (i64)>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = func.call @Main.pick(%m) : (i64) -> !idr.fn<(i64) -> (i64)>
      %h = idr.closure @Main.twice(%g) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> loc("Main.idr":16:5)
      idr.yield %h : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  // later 0 = Delay 1; later n = Delay (force (later (n - 1)))
  func.func private @Main.one() -> i64 attributes {idr.total} {
    %c1 = arith.constant 1 : i64
    return %c1 : i64
  }
  func.func private @Main.later(%n: i64 {idr.quantity = "w"}) -> !idr.fn<() -> (i64)> {
    %r = idr.match_lit %n : i64 -> (!idr.fn<() -> (i64)>) {
    case 0 {
      %f = idr.closure @Main.one() : () -> !idr.fn<() -> (i64)>
      idr.yield %f : !idr.fn<() -> (i64)>
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %g = func.call @Main.later(%m) : (i64) -> !idr.fn<() -> (i64)>
      %h = idr.closure @Main.force(%g) : (!idr.fn<() -> (i64)>) -> !idr.fn<() -> (i64)>
      idr.yield %h : !idr.fn<() -> (i64)>
    }
    }
    return %r : !idr.fn<() -> (i64)>
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %f = func.call @Main.pick(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
    %l = func.call @Main.later(%n) : (i64) -> !idr.fn<() -> (i64)>
    %s = idr.apply %l() : !idr.fn<() -> (i64)>
    %neg = idr.closure @Main.neg() : () -> !idr.fn<(i1) -> (i1)>
    %b = arith.cmpi eq, %r, %s : i64
    %nb = idr.apply %neg(%b) : !idr.fn<(i1) -> (i1)>
    %x = arith.extui %nb : i1 to i64
    %w2 = idr.io.put_int signed %x, %w1 : i64
    return %w2 : !idr.world
  }
}
