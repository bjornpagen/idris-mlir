// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// A program's root is where a run starts and where it ends: nothing calls
// it, so it takes nothing, and before the program is lowered nothing reads
// what it gives, so none of its results holds a run-time value. The rule
// binds the root alone. In the first program @step takes a word and gives
// one, and @main, the root, calls it: the program verifies. In the second
// the root takes a word; in the third the root gives one. Each is refused
// at the root.
idr.program @ordinary root(@main) stage(first) {
  idr.func @main() {
    %one = arith.constant 1 : i64
    %two = idr.call @step(%one) : (i64) -> i64
    idr.return
  }
  idr.func @step(%x: i64) -> i64 {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    idr.return %y : i64
  }
}

// -----

idr.program @takes root(@step) stage(first) {
  // expected-error @below {{}}
  idr.func @step(%x: i64) {
    idr.return
  }
}

// -----

idr.program @gives root(@answer) stage(first) {
  // expected-error @below {{}}
  idr.func @answer() -> i64 {
    %answer = arith.constant 42 : i64
    idr.return %answer : i64
  }
}
