// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-heap-allocation=@heads,checks-every-path=@other -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=no-heap-allocation=@heads' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=checks-every-path=@heads' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=no-heap-allocation=@root' -o /dev/null
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@heads
// The first character of a string built at runtime is what it was built
// from, so the string is not built: a character before a string is that
// character, and the text of a number starts with its first digit or sign
// (int_head, double_head).
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it; @heads checks nothing, and the root
// builds the string it gives @other.

idr.program @head root(@root) stage(first) {
  idr.func @heads(%c: i32, %s: !idr.str, %x: i64, %b: i16, %d: f64) -> (i32, i32, i32, i32) {
    %t = idr.str.cons %c, %s
    %h0 = idr.str.head %t
    %u = idr.str.show_sint %x : i64
    %h1 = idr.str.head %u
    %v = idr.str.show_uint %b : i16
    %h2 = idr.str.head %v
    %e = idr.str.show_double %d
    %h3 = idr.str.head %e
    return %h0, %h1, %h2, %h3 : i32, i32, i32, i32
  }

  // The head of any other string stays, after its guard, which may crash.
  idr.func @other(%s: !idr.str) -> i32 {
    %g = idr.check.nonempty %s, "head of an empty string" : !idr.str
    %h = idr.str.head %g
    return %h : i32
  }
  // The program's root runs both functions above on what it reads: the
  // byte as a character, as a number from -128 to 127 at three widths,
  // and as a quarter of it; and @other on a string of the byte, or on the
  // empty string when the byte is 0, where its guard crashes.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c128 = arith.constant 128 : i64
    %x = arith.subi %byte, %c128 : i64
    %b = arith.trunci %x : i64 to i16
    %f = arith.sitofp %x : i64 to f64
    %q = arith.constant 0.25 : f64
    %d = arith.mulf %f, %q : f64
    %zz = idr.constant !idr.str "zz"
    %h0, %h1, %h2, %h3 = idr.call @heads(%ch, %zz, %x, %b, %d) : (i32, !idr.str, i64, i16, f64) -> (i32, i32, i32, i32)
    %w1 = idr.io.put_char %h0, %w0
    %w2 = idr.io.put_char %h1, %w1
    %w3 = idr.io.put_char %h2, %w2
    %w4 = idr.io.put_char %h3, %w3
    %empty = idr.constant !idr.str ""
    %s = idr.match_lit %byte : i64 -> (!idr.str) {
    case 0 {
      idr.yield %empty : !idr.str
    }
    default(%e: i64) {
      %t = idr.str.cons %ch, %empty
      idr.yield %t : !idr.str
    }
    }
    %h = idr.call @other(%s) : (!idr.str) -> i32
    %w5 = idr.io.put_char %h, %w4
    return %w5 : !idr.world
  }
}
