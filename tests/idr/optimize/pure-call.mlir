// RUN: idris-mlir-opt %s --idr-optimize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@sum -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=not-called=@spin -o /dev/null
// A call carries its callee's effects, written once, when the caller
// becomes ready and the callee is final, before the pipeline that cleans
// the caller: so the cleanup knows what each call may do. @sum is total
// and does nothing but compute, so its call, whose result nothing reads,
// is gone, though @sum, on a cycle of its own, is never inlined. @spin is
// the same function without Idris's proof that it ends: its call may
// diverge, and stays.
idr.program @"pure-call" root(@Main.main) stage(first) {
  idr.func @sum(%n: i64, %acc: i64) -> i64 attributes {total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %a = arith.addi %acc, %n : i64
      %y = idr.call @sum(%m, %a) : (i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @spin(%n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %a = arith.addi %acc, %n : i64
      %y = idr.call @spin(%m, %a) : (i64, i64) -> i64
      idr.yield %y : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %z = arith.constant 0 : i64
    %a = idr.call @sum(%n, %z) : (i64, i64) -> i64
    %b = idr.call @spin(%n, %z) : (i64, i64) -> i64
    %w2 = idr.io.put_int signed %n, %w1 : i64
    return %w2 : !idr.world
  }
}
