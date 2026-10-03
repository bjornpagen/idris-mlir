// RUN: idris-mlir-opt %s --idr-inline | FileCheck %s --check-prefix=INLINE
// RUN: idris-mlir-opt %s --idr-contify | FileCheck %s --check-prefix=CONTIFY
// idr.total says every loop of a function's own body is one Idris proved
// terminating. A body that takes in one without that proof, by inlining or
// contification, loses it: a loop of the callee's may close there, as when
// the other function of a cycle is inlined into its breaker. One that takes
// in a proved body keeps it. The inliner inlines a helper into a loop
// breaker; contification, a case block that calls its parent back.
// INLINE-LABEL: func.func private @keeps(
// INLINE-SAME: idr.total
// INLINE-NOT: call @proved
// INLINE-LABEL: func.func private @loses(
// INLINE-NOT: idr.total
// INLINE-NOT: call @unproved
// INLINE: return
// CONTIFY-LABEL: func.func private @keeps_parent(
// CONTIFY-SAME: idr.total
// CONTIFY-NOT: call @keeps_case
// CONTIFY-LABEL: func.func private @loses_parent(
// CONTIFY-NOT: idr.total
// CONTIFY-NOT: call @loses_case
// CONTIFY: return
module attributes {idr.program} {
  func.func private @proved(%x: i64) -> i64 attributes {idr.total} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  func.func private @unproved(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  func.func private @keeps(%x: i64) -> i64 attributes {idr.total, no_inline} {
    %r = func.call @proved(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @loses(%x: i64) -> i64 attributes {idr.total, no_inline} {
    %r = func.call @unproved(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @keeps_case(%x: i64) -> i64 attributes {idr.total} {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %one = arith.constant 1 : i64
      %y = arith.subi %x, %one : i64
      %z = func.call @keeps_parent(%y) : (i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  func.func private @keeps_parent(%x: i64) -> i64 attributes {idr.total, no_inline} {
    %r = func.call @keeps_case(%x) : (i64) -> i64
    return %r : i64
  }
  func.func private @loses_case(%x: i64) -> i64 {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %z = func.call @loses_parent(%x) : (i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  func.func private @loses_parent(%x: i64) -> i64 attributes {idr.total, no_inline} {
    %r = func.call @loses_case(%x) : (i64) -> i64
    return %r : i64
  }
  func.func @Main.main(%w: !idr.world) -> !idr.world {
    %c = arith.constant 3 : i64
    %a = func.call @keeps_parent(%c) : (i64) -> i64
    %b = func.call @loses_parent(%a) : (i64) -> i64
    %d = func.call @keeps(%b) : (i64) -> i64
    %e = func.call @loses(%d) : (i64) -> i64
    %w1 = idr.io.put_int signed %e, %w : i64
    return %w1 : !idr.world
  }
}
