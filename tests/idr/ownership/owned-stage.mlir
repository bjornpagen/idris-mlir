// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: sed '/^\/\/ -----/,$d' %s > %t.before.mlir
// RUN: idris-mlir-opt %t.before.mlir --idr-rc | FileCheck %s --implicit-check-not=stage
// The owned stage is what the grades say: a program with an owned value is
// in it, and its verifier keeps the stage's rule there, with no attribute
// to say so. idr-rc writes the grades and nothing else: its output names
// no stage. A program whose owned value is never consumed is refused.
// CHECK: idr.drop
module attributes {idr.program} {
  func.func private @size(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
  func.func @Prog.main() -> i64 {
    %a = idr.constant "a" : !idr.str
    %b = idr.str.append %a, %a
    %n = func.call @size(%b) : (!idr.str) -> i64
    return %n : i64
  }
}

// -----

module attributes {idr.program} {
  // expected-note @+1 {{the value is defined here}}
  func.func private @leak(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length %v
    // expected-error @+1 {{returns while a value still holds a reference}}
    return %n : i64
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
