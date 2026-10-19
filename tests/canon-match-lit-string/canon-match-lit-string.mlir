// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@nonempty:1/1/1,matches-nothing=@nonempty,\
// RUN: returns-on-paths=@maybe_empty:0+1,returns-on-paths=@other_keys:0+1 -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=returns=@nonempty:1/1/1,matches-nothing=@nonempty,returns-on-paths=@other_keys:0+1' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=matches=@nonempty' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=returns-on-paths=@maybe_empty:1' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=returns-on-paths=@other_keys:1' -o /dev/null
// RUN: %differential %s %t.mlir
// BEFORE-DAG: expected returns: {{.*}}@nonempty
// BEFORE-DAG: expected matches-nothing: {{.*}}@nonempty
// BEFORE-DAG: expected returns-on-paths: {{.*}}@other_keys
// A string that cannot be empty never takes the case "".
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it; @nonempty matches nothing after it,
// and @maybe_empty may still return 0, @other_keys 0 too.

idr.program @"match-lit-string" root(@root) stage(first) {
  idr.func @nonempty(%x: i64, %c: i32, %s: !idr.str) -> (i64, i64, i64) {
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %shown = idr.str.show_sint %x : i64
    %a = idr.match_lit %shown : !idr.str -> (i64) {
    case "" {
      idr.yield %zero : i64
    }
    default(%d1: !idr.str) {
      idr.yield %one : i64
    }
    }
    %consed = idr.str.cons %c, %s
    %b = idr.match_lit %consed : !idr.str -> (i64) {
    case "" {
      idr.yield %zero : i64
    }
    default(%d2: !idr.str) {
      idr.yield %one : i64
    }
    }
    %lit = idr.constant !idr.str "x"
    %appended = idr.str.append %s, %lit
    %d = idr.match_lit %appended : !idr.str -> (i64) {
    case "" {
      idr.yield %zero : i64
    }
    default(%d3: !idr.str) {
      idr.yield %one : i64
    }
    }
    return %a, %b, %d : i64, i64, i64
  }

  // Any other string may be empty, so its case "" stays; of the text of a
  // number, which is never empty, the case "" goes and every other key stays.
  idr.func @maybe_empty(%s: !idr.str) -> i64 {
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %a = idr.match_lit %s : !idr.str -> (i64) {
    case "" {
      idr.yield %zero : i64
    }
    default(%d: !idr.str) {
      idr.yield %one : i64
    }
    }
    return %a : i64
  }
  idr.func @other_keys(%x: i64) -> i64 {
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %shown = idr.str.show_sint %x : i64
    %b = idr.match_lit %shown : !idr.str -> (i64) {
    case "1" {
      idr.yield %zero : i64
    }
    case "" {
      idr.yield %x : i64
    }
    default(%d: !idr.str) {
      idr.yield %one : i64
    }
    }
    return %b : i64
  }
  // The program's root runs every function above on what it reads: the
  // byte, less 128, as a number; the byte as a character; and a string of
  // it, or the empty string when the byte is 0.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c128 = arith.constant 128 : i64
    %x = arith.subi %byte, %c128 : i64
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
    %a, %b, %c = idr.call @nonempty(%x, %ch, %s) : (i64, i32, !idr.str) -> (i64, i64, i64)
    %w1 = idr.io.put_sint %a, %w0 : i64
    %w2 = idr.io.put_sint %b, %w1 : i64
    %w3 = idr.io.put_sint %c, %w2 : i64
    %r0 = idr.call @maybe_empty(%s) : (!idr.str) -> i64
    %w4 = idr.io.put_sint %r0, %w3 : i64
    %c127 = arith.constant 127 : i64
    %y = arith.subi %byte, %c127 : i64
    %r1 = idr.call @other_keys(%y) : (i64) -> i64
    %w5 = idr.io.put_sint %r1, %w4 : i64
    return %w5 : !idr.world
  }
}
