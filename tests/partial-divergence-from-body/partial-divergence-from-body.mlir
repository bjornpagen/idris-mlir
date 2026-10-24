// RUN: idris-mlir-opt %s -split-input-file --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=may-diverge=@main})' -verify-diagnostics -o /dev/null
// A function Idris did not prove to end may run forever only by what its
// body does: a loop that may not end, which says so where it repeats, or a
// call of a function that may not end, which carries its callee's row. Not
// being proved puts nothing in its row by itself.
//
// In the first program @main, which Idris did not prove, has no loop. It
// calls @descend, not proved either, which counts down by two to one, so
// an even start passes one by and the recursion never ends; nothing reads
// what @descend gives, and eager evaluation runs the call anyway.
// @descend's self call is no tail call, since it takes one from what the
// call gives, so the recursion stays a cycle of calls, whose divergence
// @main's call of it carries.
idr.program @called root(@main) stage(first) {
  idr.func @main() {
    %even = arith.constant 98 : i64
    %a = idr.call @descend(%even) : (i64) -> i64
    idr.return
  }
  idr.func @descend(%n: i64) -> i64 {
    %r = idr.lit.match %n : i64 -> (i64) {
      case 1(%key0: i64) {
        idr.yield %n : i64
      } default(%d: i64) {
        %two = arith.constant 2 : i64
        %next = arith.subi %d, %two : i64
        %t = idr.call @descend(%next) : (i64) -> i64
        %one = arith.constant 1 : i64
        %s = arith.subi %t, %one : i64
        idr.yield %s : i64
      }
    }
    idr.return %r : i64
  }
}

// -----

// In the second @main, which Idris did not prove, has neither loop nor
// call, so a run of it always ends, and its row says so.
idr.program @alone root(@main) stage(first) {
  // expected-error @below {{expected may-diverge: }}
  idr.func @main() {
    idr.return
  }
}
