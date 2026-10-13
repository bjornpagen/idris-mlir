// RUN: idris-mlir-opt %s --idr-inline | FileCheck %s --check-prefix=INLINE
// RUN: idris-mlir-opt %s --idr-contify | FileCheck %s --check-prefix=CONTIFY
// The fact total says every loop of a function's own body is one Idris
// proved terminating. A body that takes in one without that proof, by
// inlining or contification, loses it: a loop of the callee's may close
// there, as when the other function of a cycle is inlined into its
// breaker. One that takes in a proved body keeps it. The inliner inlines
// a helper into a loop breaker; contification, a case block that calls its
// parent back.
// INLINE-LABEL: idr.func private @keeps(
// INLINE-SAME: total
// INLINE-NOT: call @proved
// INLINE-LABEL: idr.func private @loses(
// INLINE-NOT: {{[{ ]}}total{{[,}]}}
// INLINE-NOT: call @unproved
// INLINE: return
// CONTIFY-LABEL: idr.func private @keeps_parent(
// CONTIFY-SAME: total
// CONTIFY-NOT: call @keeps_case
// CONTIFY-LABEL: idr.func private @loses_parent(
// CONTIFY-NOT: {{[{ ]}}total{{[,}]}}
// CONTIFY-NOT: call @loses_case
// CONTIFY: return
module attributes {idr.program} {
  idr.func private @proved(%x: i64) -> i64 attributes {total} {
    %r = arith.addi %x, %x : i64
    return %r : i64
  }
  idr.func private @unproved(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func private @keeps(%x: i64) -> i64 attributes {total, no_inline} {
    %r = idr.call @proved(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func private @loses(%x: i64) -> i64 attributes {total, no_inline} {
    %r = idr.call @unproved(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func private @keeps_case(%x: i64) -> i64 attributes {total} {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %one = arith.constant 1 : i64
      %y = arith.subi %x, %one : i64
      %z = idr.call @keeps_parent(%y) : (i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func private @keeps_parent(%x: i64) -> i64 attributes {total, no_inline} {
    %r = idr.call @keeps_case(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func private @loses_case(%x: i64) -> i64 {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %x : i64
    }
    default {
      %z = idr.call @loses_parent(%x) : (i64) -> i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func private @loses_parent(%x: i64) -> i64 attributes {total, no_inline} {
    %r = idr.call @loses_case(%x) : (i64) -> i64
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c = arith.constant 3 : i64
    %a = idr.call @keeps_parent(%c) : (i64) -> i64
    %b = idr.call @loses_parent(%a) : (i64) -> i64
    %d = idr.call @keeps(%b) : (i64) -> i64
    %e = idr.call @loses(%d) : (i64) -> i64
    %w1 = idr.io.put_int signed %e, %w : i64
    return %w1 : !idr.world
  }
}
