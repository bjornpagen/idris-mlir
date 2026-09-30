// RUN: idris-mlir-opt %s -split-input-file --remove-dead-values | FileCheck %s --check-prefix=RDV
// RUN: idris-mlir-opt %s -split-input-file --inline | FileCheck %s --check-prefix=INLINE
// Upstream's remove-dead-values and inline work on matches and closures. A
// function whose body is a crash returns ub.poison after it,
// so the inliner inlines it: it cannot inline a body that ends in
// ub.unreachable (upstream/inline-unreachable-terminator). Every private
// function here has a caller: remove-dead-values at the pin erases the
// arguments of a function it finds unreachable but keeps their uses
// (upstream/remove-dead-values-unreachable), which idr-prune prevents in the
// pipeline.

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
    %never = ub.poison : i64
    return %never : i64
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
    %never = ub.poison : i64
    return %never : i64
  }
  // INLINE-LABEL: func.func @crash_inlined
  // INLINE: idr.match_lit
  // INLINE: default {
  // INLINE-NEXT: idr.crash "unhandled input for fail"
  // INLINE-NEXT: idr.yield %{{.*}} : i64
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
}
