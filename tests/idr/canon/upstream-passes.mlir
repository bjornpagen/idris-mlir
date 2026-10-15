// RUN: sed '/^\/\/ -----/,$d' %s > %t.first.mlir
// RUN: awk '/^\/\/ -----/ { n++; next } n == 1' %s > %t.second.mlir
// RUN: idris-mlir-opt %t.first.mlir --remove-dead-values --idr-expect=holds=matches=@get,applies=@get,\
// RUN: calls=@get:@fail,parameters-used=@get,parameters-used=@fail -o /dev/null
// RUN: idris-mlir-opt %t.first.mlir --inline --idr-expect=holds=returns=@main:8 -o /dev/null
// RUN: idris-mlir-opt %t.second.mlir --inline --idr-expect=holds=calls=@crash_inlined:@fail,\
// RUN: never-returns=@crash_in_body,never-calls=@crash_in_body:@fail -o /dev/null
// RUN: idris-mlir-opt %t.second.mlir --remove-dead-values --idr-expect=holds=parameters-used=@fail -o /dev/null
// RUN: idris-mlir-opt %s -split-input-file --canonicalize=test-convergence=true -o /dev/null
// Upstream's remove-dead-values and inline work on matches and closures. A
// function whose body is a crash ends in ub.unreachable after it; the
// inliner inlines it into a function body, the block after the call
// following in a block that nothing reaches, but not into a match region,
// which is one block (SingleBlock). Remove-dead-values drops a parameter
// nothing reads and a result nothing uses, and keeps the match, its apply
// and its call.

!Maybe = !idr.data<"Maybe", plain [@Nothing(), @Just(i64)]>
idr.program @"upstream-passes" root(@main) stage(higher) {
  idr.func @inc(%k: i64, %x: i64) -> i64
      attributes {total} {
    %r = arith.addi %k, %x : i64
    return %r : i64
  }
  idr.func @fail(%x: i64) -> i64 {
    idr.crash "unhandled input for fail"
    ub.unreachable
  }
  idr.func @get(%m: !Maybe, %d: i64,
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
  idr.func @main() -> i64 {
    %n = arith.constant 4 : i64
    %m = idr.con !Maybe @Just(%n : i64)
    %r, %s = idr.call @get(%m, %n, %n) : (!Maybe, i64, i64) -> (i64, i64)
    return %r : i64
  }
}

// -----

idr.program @"upstream-passes" root(@root) stage(first) {
  idr.func @fail(%x: i64) -> i64 {
    idr.crash "unhandled input for fail"
    ub.unreachable
  }
  idr.func @crash_inlined(%x: i64) -> i64 {
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
  idr.func @crash_in_body(%x: i64) -> i64 {
    %f = idr.call @fail(%x) : (i64) -> i64
    %c1 = arith.constant 1 : i64
    %r = arith.addi %f, %c1 : i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
