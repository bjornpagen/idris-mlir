// NEEDS-ACCEPTANCE: that contified holds of the module pulled out of the CLEAN lines and fails once, at the one call of @step.case.
// RUN: sed -n 's|^// CLEAN: ||p' %s > %t.clean.mlir
// RUN: idris-mlir-opt %t.clean.mlir --idr-expect=holds=contified -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=contified -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 1
// A function called once, from a function it calls back, is a
// continuation of that function, still out of line (@step.case, the case
// block of @step's `if`); a recursion that is one function has none (the
// module of the CLEAN lines).
// CHECK-DAG: error: expected contified: @step.case is called once, from {{.*}}, and is still a function
// CLEAN: idr.program @clean root(@root) stage(first) {
// CLEAN:   idr.func @step(%n: i64, %acc: i64) -> i64 {
// CLEAN:     %r = idr.match_lit %n : i64 -> (i64) {
// CLEAN:     case 0 {
// CLEAN:       idr.yield %acc : i64
// CLEAN:     }
// CLEAN:     default {
// CLEAN:       %c1 = arith.constant 1 : i64
// CLEAN:       %m = arith.subi %n, %c1 : i64
// CLEAN:       %s = idr.call @step(%m, %acc) : (i64, i64) -> i64
// CLEAN:       idr.yield %s : i64
// CLEAN:     }
// CLEAN:     }
// CLEAN:     return %r : i64
// CLEAN:   }
// CLEAN:   idr.func @root() -> i64 {
// CLEAN:     %n = arith.constant 3 : i64
// CLEAN:     %z = arith.constant 0 : i64
// CLEAN:     %r = idr.call @step(%n, %z) : (i64, i64) -> i64
// CLEAN:     return %r : i64
// CLEAN:   }
// CLEAN: }
idr.program @continuations root(@root) stage(first) {
  idr.func @step(%n: i64, %acc: i64) -> i64 {
    %c0 = arith.constant 0 : i64
    %done = arith.cmpi sle, %n, %c0 : i64
    %r = idr.call @step.case(%done, %n, %acc) : (i1, i64, i64) -> i64
    return %r : i64
  }
  idr.func @step.case(%done: i1, %n: i64, %acc: i64) -> i64 {
    %r = idr.match_lit %done : i1 -> (i64) {
    case 1 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %s = idr.call @step(%m, %acc) : (i64, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @root() -> i64 {
    %n = arith.constant 3 : i64
    %z = arith.constant 0 : i64
    %r = idr.call @step(%n, %z) : (i64, i64) -> i64
    return %r : i64
  }
}
