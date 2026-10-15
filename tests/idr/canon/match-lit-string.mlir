// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@nonempty:1/1/1,matches-nothing=@nonempty,\
// RUN: returns-on-paths=@maybe_empty:0+1,returns-on-paths=@other_keys:0+1 -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// A string that cannot be empty never takes the case "".

idr.program @"match-lit-string" root(@root) stage(first) {
  idr.func @nonempty(%x: i64, %c: i32, %s: !idr.str) -> (i64, i64, i64) {
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %shown = idr.str.show signed %x : i64
    %a = idr.match_lit %shown : !idr.str -> (i64) {
    case "" {
      idr.yield %zero : i64
    }
    default {
      idr.yield %one : i64
    }
    }
    %consed = idr.str.cons %c, %s
    %b = idr.match_lit %consed : !idr.str -> (i64) {
    case "" {
      idr.yield %zero : i64
    }
    default {
      idr.yield %one : i64
    }
    }
    %lit = idr.constant "x" : !idr.str
    %appended = idr.str.append %s, %lit
    %d = idr.match_lit %appended : !idr.str -> (i64) {
    case "" {
      idr.yield %zero : i64
    }
    default {
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
    default {
      idr.yield %one : i64
    }
    }
    return %a : i64
  }
  idr.func @other_keys(%x: i64) -> i64 {
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %shown = idr.str.show signed %x : i64
    %b = idr.match_lit %shown : !idr.str -> (i64) {
    case "1" {
      idr.yield %zero : i64
    }
    case "" {
      idr.yield %x : i64
    }
    default {
      idr.yield %one : i64
    }
    }
    return %b : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
