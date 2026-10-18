// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-heap-allocation=@heads,checks-every-path=@other -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// The first character of a string built at runtime is what it was built
// from, so the string is not built: a character before a string is that
// character, and the text of a number starts with its first digit or sign
// (int_head, double_head).

idr.program @head root(@root) stage(first) {
  idr.func @heads(%c: i32, %s: !idr.str, %x: i64, %b: i16, %d: f64) -> (i32, i32, i32, i32) {
    %t = idr.str.cons %c, %s
    %h0 = idr.str.head %t
    %u = idr.str.show signed %x : i64
    %h1 = idr.str.head %u
    %v = idr.str.show unsigned %b : i16
    %h2 = idr.str.head %v
    %e = idr.str.show %d : f64
    %h3 = idr.str.head %e
    return %h0, %h1, %h2, %h3 : i32, i32, i32, i32
  }

  // The head of any other string stays, after its guard, which may crash.
  idr.func @other(%s: !idr.str) -> i32 {
    %g = idr.check.nonempty %s, "head of an empty string" : !idr.str
    %h = idr.str.head %g
    return %h : i32
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
