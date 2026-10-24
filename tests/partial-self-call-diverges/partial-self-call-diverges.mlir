// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A function that calls itself closes a cycle of one, which ends only where
// Idris proved the function. The call holds its callee's row, here the
// function's own, so it can only repeat what that row says: the function's
// verifier reads the cycle off the function instead, and a function Idris
// did not prove whose row holds no divergence is refused, at its call of
// itself. @descend counts down by one to zero and adds one back on the way
// out, so its self call is no tail call and stays a cycle of calls. The
// refused module differs from the first by its row alone, and from the
// third by its proof alone, so the refusal is the cycle's.

// Not proved, and its row holds the cycle's divergence.
idr.program @rows root(@main) stage(first) {
  idr.func <{row = []}> @main() {
    idr.return
  }
  idr.func <{row = ["divergence"]}> @descend(%n: i64) -> i64 {
    %r = idr.lit.match %n : i64 -> (i64) {
      case 0(%key0: i64) {
        idr.yield %n : i64
      } default(%d: i64) {
        %one = arith.constant 1 : i64
        %next = arith.subi %d, %one : i64
        %t = idr.call @descend(%next) <{row = ["divergence"]}> : (i64) -> i64
        %s = arith.addi %t, %one : i64
        idr.yield %s : i64
      }
    }
    idr.return %r : i64
  }
}

// -----

// Not proved, and its row holds nothing.
idr.program @rows root(@main) stage(first) {
  idr.func <{row = []}> @main() {
    idr.return
  }
  // expected-error @below {{}}
  idr.func <{row = []}> @descend(%n: i64) -> i64 {
    %r = idr.lit.match %n : i64 -> (i64) {
      case 0(%key1: i64) {
        idr.yield %n : i64
      } default(%d: i64) {
        %one = arith.constant 1 : i64
        %next = arith.subi %d, %one : i64
        // expected-note @below {{}}
        %t = idr.call @descend(%next) <{row = []}> : (i64) -> i64
        %s = arith.addi %t, %one : i64
        idr.yield %s : i64
      }
    }
    idr.return %r : i64
  }
}

// -----

// Proved, by the attribute that holds Idris's proof, and its row holds
// nothing.
idr.program @rows root(@main) stage(first) {
  idr.func <{row = []}> @main() {
    idr.return
  }
  idr.func <{row = []}> @descend(%n: i64) -> i64 attributes {terminates = #idr.terminates} {
    %r = idr.lit.match %n : i64 -> (i64) {
      case 0(%key2: i64) {
        idr.yield %n : i64
      } default(%d: i64) {
        %one = arith.constant 1 : i64
        %next = arith.subi %d, %one : i64
        %t = idr.call @descend(%next) <{row = []}> : (i64) -> i64
        %s = arith.addi %t, %one : i64
        idr.yield %s : i64
      }
    }
    idr.return %r : i64
  }
}
