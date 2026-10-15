// RUN: idris-mlir-opt %s --remove-dead-values=canonicalize=false --symbol-dce | FileCheck %s
// RUN: idris-mlir-opt %s --remove-dead-values --symbol-dce | FileCheck %s --check-prefix=CANON
// The match region that the constant 1 rules out, and @g, which only that
// region calls, are unreachable. remove-dead-values, as the simplify round
// runs it, erases @g's argument and the result the region used, and gives
// their remaining uses poison: the module stays valid
// (upstream/06-remove-dead-values-unreachable). With its canonicalization the
// dead region goes, and symbol-dce then removes @g.
// CHECK-LABEL: idr.func @g(
// CHECK-NEXT: %[[P:.*]] = ub.poison : i64
// CHECK-NEXT: match_lit %[[P]]
// CHECK-LABEL: idr.func @Main.main(
// CHECK: case 0 {
// CHECK-NEXT: call @g()
// CHECK-NEXT: %[[Q:.*]] = ub.poison : i64
// CHECK-NEXT: idr.yield %[[Q]]
// CANON-NOT: @g
// CANON-LABEL: idr.func @Main.main(
// CANON-NOT: {{(idr\.| )match_lit }}
// CANON: return
idr.program @"rdv-unreachable" root(@Main.main) stage(first) {
  idr.func @g(%x: i64) -> i64 {
    %r = idr.match_lit %x : i64 -> (i64) {
    case 7 {
      idr.crash "seven"
      ub.unreachable
    }
    default {
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main() -> i64 {
    %c1 = arith.constant 1 : i64
    %r = idr.match_lit %c1 : i64 -> (i64) {
    case 0 {
      %y = idr.call @g(%c1) : (i64) -> i64
      idr.yield %y : i64
    }
    default {
      idr.yield %c1 : i64
    }
    }
    return %r : i64
  }
}
