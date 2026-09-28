// RUN: %status 1 idris-mlir-opt %s --split-input-file --idr-check-profile -o %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.err
// rule: DIAG-LOC-1, DIAG-ONE-1, PROF-TYPE-4, PROF-HEAP-3
// Library code inlined into user code: the error is reported at the
// innermost user location of the op's call-site chain, names the library
// location in parentheses, and notes the callers.
// CHECK: Main.idr:11:3: error: unsupported (PROF-TYPE-4): Integer computed at runtime by idr.big.from_int, which may allocate (in Prelude/Cast.idr:83:1)
// CHECK-NEXT: Main.idr:20:1: note: called from here
module attributes {idr.program} {
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %b = idr.big.from_int signed %n : i64 loc(callsite(fused<"library">["Prelude/Cast.idr":83:1] at callsite("Main.idr":11:3 at "Main.idr":20:1)))
    %t = idr.big.to_int %b : i64
    %w2 = idr.io.put_int signed %t, %w1 : i64
    return %w2 : !idr.world
  }
}

// -----

// Two violations: only the first in op order is reported.
// CHECK: Main.idr:30:1: error: unsupported (PROF-HEAP-3)
// CHECK-NOT: error:
module attributes {idr.program} {
  func.func private @show(%x: i64 {idr.quantity = "w"}) -> !idr.str {
    %s = idr.str.show signed %x : i64 loc("Main.idr":30:1)
    return %s : !idr.str
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.world {
    %c, %w1 = idr.io.get_char %w
    %n = arith.extui %c : i32 to i64
    %b = idr.big.from_int signed %n : i64 loc("Main.idr":31:1)
    %s = func.call @show(%n) : (i64) -> !idr.str
    %w2 = idr.io.put_str %s, %w1
    %t = idr.big.to_int %b : i64
    %w3 = idr.io.put_int signed %t, %w2 : i64
    return %w3 : !idr.world
  }
}
