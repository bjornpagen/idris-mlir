// NEEDS-ACCEPTANCE: that sinking reads a call's own effects, its callee's written on it once the callee is final (mlir-12), so the call of the total @pmk moves into the one region that applies its result and is raised there, while the call of the partial @mk stays before the match, where calls-where-used reports it at its line (mlir-22) (S2's default argument).
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=calls-where-used=@Main.main:@pmk -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce),idr-expect{holds=calls-where-used=@Main.main:@mk})' -verify-diagnostics -o /dev/null
// A call whose result only one region of a later match applies moves into
// that region when its callee only computes: there the apply eliminates
// the call's result, which raising then takes into a copy of the callee,
// and the call runs only on the path that uses it. What a call may do is
// its own effects, its callee's written on it once the callee is final,
// which sinking reads off the call. @pmk is total
// and computes only, so its call moves; @mk is the same function without
// Idris's proof that it ends, so its call may not return, and it stays
// where it runs on every path. Both loop, so neither is inlined.
idr.program @"sunk-call" root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @mk(%a: i64, %k: i64) -> !idr.fn<(i64) -> (i64)> {
    %r = idr.match_lit %k : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %v = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %v = idr.call @mk(%a, %m) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @pmk(%a: i64, %k: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %r = idr.match_lit %k : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %v = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    default(%d: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %v = idr.call @pmk(%a, %m) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %f = idr.call @pmk(%n, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      %z = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    default(%d: i64) {
      idr.yield %n : i64
    }
    }
    // expected-error @below {{a call of @mk in @Main.main runs where only the regions of a later op use it}}
    %g = idr.call @mk(%r, %r) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %s = idr.match_lit %r : i64 -> (i64) {
    case 0 {
      %z = idr.apply %g(%r) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    default(%d: i64) {
      idr.yield %r : i64
    }
    }
    %w2 = idr.io.put_int signed %s, %w1 : i64
    return %w2 : !idr.world
  }
}
