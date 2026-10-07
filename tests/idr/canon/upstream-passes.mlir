// RUN: idris-mlir-opt %s -split-input-file --remove-dead-values | FileCheck %s --check-prefix=RDV
// RUN: idris-mlir-opt %s -split-input-file --inline | FileCheck %s --check-prefix=INLINE
// Upstream's remove-dead-values and inline work on matches and closures. A
// function whose body is a crash ends in ub.unreachable after it; the
// inliner inlines it into a function body, the block after the call
// following in a block that nothing reaches, but not into a match region,
// which is one block (SingleBlock).

module attributes {idr.program} {
  idr.data @Maybe {
    idr.ctor @Nothing ()
    idr.ctor @Just (i64)
  }
  func.func private @inc(%k: i64, %x: i64) -> i64
      attributes {idr.total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  func.func private @fail(%x: i64) -> i64 {
    idr.crash "unhandled input for fail"
    ub.unreachable
  }
  // RDV-LABEL: func.func private @get(
  // RDV-SAME: %{{.*}}: !idr.data<@Maybe>, %[[D:.*]]: i64) -> i64 {
  // RDV: %[[R:.*]] = idr.match %{{.*}} : !idr.data<@Maybe> -> (i64) {
  // RDV: idr.apply
  // RDV: default {
  // RDV-NEXT: call @fail()
  // RDV: return %[[R]] : i64
  func.func private @get(%m: !idr.data<@Maybe>, %d: i64,
                         %unused: i64) -> (i64, i64) {
    %r, %s = idr.match %m : !idr.data<@Maybe> -> (i64, i64) {
    case @Just(%x: i64) {
      %c = idr.closure @inc(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
      %y = idr.apply %c(%d) : !idr.fn<(i64) -> (i64)>
      idr.yield %y, %unused : i64, i64
    }
    default {
      %f = func.call @fail(%d) : (i64) -> i64
      idr.yield %f, %d : i64, i64
    }
    }
    return %r, %s : i64, i64
  }
  // INLINE-LABEL: func.func @main
  // INLINE-NEXT: %[[C:.*]] = arith.constant 8 : i64
  // INLINE-NEXT: return %[[C]] : i64
  // RDV-LABEL: func.func @main
  // RDV: call @get(%{{.*}}, %{{.*}}) : (!idr.data<@Maybe>, i64) -> i64
  func.func @main() -> i64 {
    %n = arith.constant 4 : i64
    %m = idr.con @Maybe::@Just(%n) : (i64) -> !idr.data<@Maybe>
    %r, %s = func.call @get(%m, %n, %n) : (!idr.data<@Maybe>, i64, i64) -> (i64, i64)
    return %r : i64
  }
}

// -----

module {
  func.func private @fail(%x: i64) -> i64 {
    idr.crash "unhandled input for fail"
    ub.unreachable
  }
  // INLINE-LABEL: func.func @crash_inlined
  // INLINE: idr.match_lit
  // INLINE: default {
  // INLINE-NEXT: call @fail(
  // INLINE-NEXT: idr.yield %{{.*}} : i64
  // INLINE-LABEL: func.func @crash_in_body
  // INLINE-NEXT: idr.crash "unhandled input for fail"
  // INLINE-NEXT: ub.unreachable
  // INLINE-NEXT: }
  // RDV-LABEL: func.func @crash_inlined
  // RDV: default {
  // RDV-NEXT: call @fail()
  func.func @crash_inlined(%x: i64) -> i64 {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %f = func.call @fail(%x) : (i64) -> i64
      idr.yield %f : i64
    }
    }
    return %r : i64
  }
  func.func @crash_in_body(%x: i64) -> i64 {
    %f = func.call @fail(%x) : (i64) -> i64
    %c1 = arith.constant 1 : i64
    %r = arith.addi %f, %c1 : i64
    return %r : i64
  }
}
