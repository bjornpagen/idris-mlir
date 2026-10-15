// RUN: idris-mlir-opt %s -split-input-file --remove-dead-values | FileCheck %s --check-prefix=RDV
// RUN: idris-mlir-opt %s -split-input-file --inline | FileCheck %s --check-prefix=INLINE
// RUN: idris-mlir-opt %s -split-input-file --canonicalize=test-convergence=true -o /dev/null
// Upstream's remove-dead-values and inline work on matches and closures. A
// function whose body is a crash ends in ub.unreachable after it; the
// inliner inlines it into a function body, the block after the call
// following in a block that nothing reaches, but not into a match region,
// which is one block (SingleBlock).

!Maybe = !idr.data<"Maybe", plain [@Nothing(), @Just(i64)]>
module {
  idr.func private @inc(%k: i64, %x: i64) -> i64
      attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func private @fail(%x: i64) -> i64 {
    idr.crash "unhandled input for fail"
    ub.unreachable
  }
  // RDV-LABEL: idr.func private @get(
  // RDV-SAME: %{{.*}}: !Maybe, %[[D:.*]]: i64) -> i64 {
  // RDV: %[[R:.*]] = {{(idr\.)?}}match %{{.*}} : !Maybe -> (i64) {
  // RDV: apply
  // RDV: default {
  // RDV-NEXT: call @fail()
  // RDV: return %[[R]] : i64
  idr.func private @get(%m: !Maybe, %d: i64,
                         %unused: i64) -> (i64, i64) {
    %r, %s = idr.match %m : !Maybe -> (i64, i64) {
    case @Just(%x: i64) {
      %c = idr.closure @inc(%x) : (i64) -> !idr.fn<(i64) -> (i64)>
      %y = idr.apply %c(%d) : !idr.fn<(i64) -> (i64)>
      idr.yield %y, %unused : i64, i64
    }
    default {
      %f = idr.call @fail(%d) : (i64) -> i64
      idr.yield %f, %d : i64, i64
    }
    }
    return %r, %s : i64, i64
  }
  // INLINE-LABEL: idr.func @main
  // INLINE-NEXT: %[[C:.*]] = arith.constant 8 : i64
  // INLINE-NEXT: return %[[C]] : i64
  // RDV-LABEL: idr.func @main
  // RDV: call @get(%{{.*}}, %{{.*}}) : (!Maybe, i64) -> i64
  idr.func @main() -> i64 {
    %n = arith.constant 4 : i64
    %m = idr.con @Just(%n) : (i64) -> !Maybe
    %r, %s = idr.call @get(%m, %n, %n) : (!Maybe, i64, i64) -> (i64, i64)
    return %r : i64
  }
}

// -----

module {
  idr.func private @fail(%x: i64) -> i64 {
    idr.crash "unhandled input for fail"
    ub.unreachable
  }
  // INLINE-LABEL: idr.func private @crash_inlined
  // INLINE: match_lit
  // INLINE: default {
  // INLINE-NEXT: call @fail(
  // INLINE-NEXT: idr.yield %{{.*}} : i64
  // INLINE-LABEL: idr.func private @crash_in_body
  // INLINE-NEXT: crash "unhandled input for fail"
  // INLINE-NEXT: ub.unreachable
  // INLINE-NEXT: }
  // RDV-LABEL: idr.func private @crash_inlined
  // RDV: default {
  // RDV-NEXT: call @fail()
  idr.func private @crash_inlined(%x: i64) -> i64 {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %f = idr.call @fail(%x) : (i64) -> i64
      idr.yield %f : i64
    }
    }
    return %r : i64
  }
  idr.func private @crash_in_body(%x: i64) -> i64 {
    %f = idr.call @fail(%x) : (i64) -> i64
    %c1 = arith.constant 1 : i64
    %r = arith.addi %f, %c1 : i64
    return %r : i64
  }
}
