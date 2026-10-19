// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=results-used=@unused,matches=@unused,\
// RUN: returns-argument=@same:1,matches-nothing=@same,results-used=@dead,crash-sites=@dead:1 -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=results-used=@unused,returns-argument=@same:1,matches-nothing=@same,results-used=@dead' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=matches-nothing=@unused' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=crash-sites=@dead:0' -o /dev/null
// RUN: %differential %s %t.mlir
// BEFORE-DAG: expected results-used: {{.*}}@unused
// BEFORE-DAG: expected returns-argument: {{.*}}@same
// BEFORE-DAG: expected matches-nothing: {{.*}}@same
// BEFORE-DAG: expected results-used: {{.*}}@dead
// Results no one uses are dropped, and a result that every region yields
// from the same outer value is that value (upstream's region patterns).
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it; @unused still matches, and @dead may
// still crash, once.

!B = !idr.data<"B", plain [@F(), @T()]>
idr.program @"match-results" root(@root) stage(first) {
  idr.func @unused(%b: !B, %x: i64, %y: i64) -> i64 {
    %r:2 = idr.match %b : !B -> (i64, i64) {
    case @F() {
      %s = arith.addi %x, %y : i64
      idr.yield %s, %x : i64, i64
    }
    case @T() {
      %s = arith.subi %x, %y : i64
      idr.yield %s, %y : i64, i64
    }
    }
    return %r#0 : i64
  }

  idr.func @same(%b: !B, %x: i64, %c: i32) -> i64 {
    %r = idr.match %b : !B -> (i64) {
    case @F() {
      idr.yield %x : i64
    }
    case @T() {
      idr.yield %x : i64
    }
    }
    return %r : i64
  }

  // A match without effects whose results are unused is dead code; one that
  // may crash is not: a crash is an effect.
  idr.func @dead(%n: i64) {
    %a = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default(%d: i64) {
      %m = arith.muli %n, %n : i64
      idr.yield %m : i64
    }
    }
    %b = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    default(%d1: i64) {
      idr.crash "no"
      ub.unreachable
    }
    }
    return
  }
  // The program's root runs every function above on what it reads: a
  // constructor by the byte's low bit, and the rest of it as numbers;
  // @dead last, on 0 when the second bit is clear and on the rest of the
  // byte, where it crashes, when it is set.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c2 = arith.constant 2 : i64
    %c3 = arith.constant 3 : i64
    %c100 = arith.constant 100 : i64
    %bit = arith.andi %byte, %c1 : i64
    %second = arith.andi %byte, %c2 : i64
    %x = arith.shrui %byte, %c2 : i64
    %y = arith.subi %c100, %byte : i64
    %b = idr.match_lit %bit : i64 -> (!B) {
    case 0 {
      %f = idr.con !B @F()
      idr.yield %f : !B
    }
    default(%d: i64) {
      %t = idr.con !B @T()
      idr.yield %t : !B
    }
    }
    %r0 = idr.call @unused(%b, %x, %y) : (!B, i64, i64) -> i64
    %w1 = idr.io.put_sint %r0, %w0 : i64
    %r1 = idr.call @same(%b, %y, %ch) : (!B, i64, i32) -> i64
    %w2 = idr.io.put_sint %r1, %w1 : i64
    %n = arith.muli %second, %x : i64
    idr.call @dead(%n) : (i64) -> ()
    %w3 = idr.io.put_sint %n, %w2 : i64
    return %w3 : !idr.world
  }
}
