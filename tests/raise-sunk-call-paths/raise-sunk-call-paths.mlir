// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce))' -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=calls-where-used=@every_crash:@cmk,calls-where-used=@every_diverge:@dmk,calls-where-used=@pure_after_output:@pmk,crashes-before-output=@crash_after_output,calls-where-used=@one_linear:@lmk -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr.program(idr-defunctionalize,idr-optimize,symbol-dce),idr-expect{holds=calls-where-used=@one_crash:@cmk,calls-where-used=@crash_after_output:@cmk})' -verify-diagnostics -o /dev/null
// RUN: idris-mlir-opt %t.mlir --idr-rc --idr-expect=holds=stage=owned -o /dev/null
// A call does what its own effects say, its callee's written on it once
// the callee is final, which the canonicalizer reads off the call. A call
// that only computes moves into the regions of a later match that use its
// result, past anything (@pure_after_output, past output). One that may crash
// (@cmk) or not return (@dmk) moves only when every region uses it and only
// computing comes between (@every_crash, @every_diverge), so that every
// path still runs it before anything it could hide: used by one region it
// stays (@one_crash), and output after it keeps it before the output
// (@crash_after_output). A pure call taking a linear string moves into the
// one region that applies its result (@one_linear): on the other path
// nothing uses the string, and a linear value is used at most once on
// every path, so counting releases it there, as the owned verifier checks
// after idr-rc (the last RUN line). Each match is on a value no call takes,
// so no region knows a call's arguments and folds it; every function that
// holds a match is never inlined, and every callee that builds a closure
// is on a cycle of its own.
idr.program @"sunk-call-paths" root(@Main.main) stage(higher) {
  idr.func @add(%a: i64, %x: i64) -> i64 attributes {total} {
    %y = arith.addi %a, %x : i64
    return %y : i64
  }
  idr.func @pmk(%a: i64, %k: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %r = idr.match_lit %k : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %v = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    default(%d2: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %v = idr.call @pmk(%a, %m) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @dmk(%a: i64, %k: i64) -> !idr.fn<(i64) -> (i64)> {
    %r = idr.match_lit %k : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %v = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    default(%d2: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %v = idr.call @dmk(%a, %m) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @cmk(%a: i64, %k: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %r = idr.match_lit %k : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %v = idr.closure @add(%a) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    default(%d2: i64) {
      %d = idr.check.nonzero %a, "division by zero" : i64
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %v = idr.call @cmk(%d, %m) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @lmk(%l: !idr.lin<!idr.str>, %k: i64) -> !idr.fn<(i64) -> (i64)> attributes {total} {
    %s = idr.lin.use %l : !idr.lin<!idr.str>
    %r = idr.match_lit %k : i64 -> (!idr.fn<(i64) -> (i64)>) {
    case 0 {
      %n = idr.str.length %s
      %v = idr.closure @add(%n) : (i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    default(%d2: i64) {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %k, %c1 : i64
      %l1 = idr.lin.enter %s : !idr.lin<!idr.str>
      %v = idr.call @lmk(%l1, %m) : (!idr.lin<!idr.str>, i64) -> !idr.fn<(i64) -> (i64)>
      idr.yield %v : !idr.fn<(i64) -> (i64)>
    }
    }
    return %r : !idr.fn<(i64) -> (i64)>
  }
  idr.func @every_crash(%n: i64, %b: i64) -> i64 attributes {no_inline} {
    %f = idr.call @cmk(%n, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      %z = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    default(%d2: i64) {
      %z = idr.apply %f(%b) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @one_crash(%n: i64, %b: i64) -> i64 attributes {no_inline} {
    // expected-error @below {{a call of @cmk in @one_crash runs where only the regions of a later op use it}}
    %f = idr.call @cmk(%n, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      %z = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    default(%d2: i64) {
      idr.yield %n : i64
    }
    }
    return %r : i64
  }
  idr.func @every_diverge(%n: i64, %b: i64) -> i64 attributes {no_inline} {
    %f = idr.call @dmk(%n, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      %z = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    default(%d2: i64) {
      %z = idr.apply %f(%b) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @crash_after_output(%n: i64, %b: i64, %w: !idr.world) -> (i64, !idr.world) attributes {no_inline} {
    // expected-error @below {{a call of @cmk in @crash_after_output runs where only the regions of a later op use it}}
    %f = idr.call @cmk(%n, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %w1 = idr.io.put_sint %n, %w : i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      %z = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    default(%d2: i64) {
      %z = idr.apply %f(%b) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    }
    return %r, %w1 : i64, !idr.world
  }
  idr.func @pure_after_output(%n: i64, %b: i64, %w: !idr.world) -> (i64, !idr.world) attributes {no_inline} {
    %f = idr.call @pmk(%n, %n) : (i64, i64) -> !idr.fn<(i64) -> (i64)>
    %w1 = idr.io.put_sint %n, %w : i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      %z = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    default(%d2: i64) {
      idr.yield %n : i64
    }
    }
    return %r, %w1 : i64, !idr.world
  }
  idr.func @one_linear(%n: i64, %b: i64) -> i64 attributes {no_inline} {
    %s = idr.str.show_sint %n : i64
    %l = idr.lin.enter %s : !idr.lin<!idr.str>
    %f = idr.call @lmk(%l, %n) : (!idr.lin<!idr.str>, i64) -> !idr.fn<(i64) -> (i64)>
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      %z = idr.apply %f(%n) : !idr.fn<(i64) -> (i64)>
      idr.yield %z : i64
    }
    default(%d2: i64) {
      idr.yield %n : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %e, %w2 = idr.io.get_byte %w1
    %b = arith.extui %e : i32 to i64
    %r1 = idr.call @every_crash(%n, %b) : (i64, i64) -> i64
    %r2 = idr.call @one_crash(%n, %b) : (i64, i64) -> i64
    %r3 = idr.call @every_diverge(%n, %b) : (i64, i64) -> i64
    %r4, %w3 = idr.call @crash_after_output(%n, %b, %w2) : (i64, i64, !idr.world) -> (i64, !idr.world)
    %r5, %w4 = idr.call @pure_after_output(%n, %b, %w3) : (i64, i64, !idr.world) -> (i64, !idr.world)
    %r6 = idr.call @one_linear(%n, %b) : (i64, i64) -> i64
    %t1 = arith.addi %r1, %r2 : i64
    %t2 = arith.addi %t1, %r3 : i64
    %t3 = arith.addi %t2, %r4 : i64
    %t4 = arith.addi %t3, %r5 : i64
    %t = arith.addi %t4, %r6 : i64
    %w5 = idr.io.put_sint %t, %w4 : i64
    return %w5 : !idr.world
  }
}
