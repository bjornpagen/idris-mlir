// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=regions-distinct=@into_default,matches=@into_default,\
// RUN: regions-distinct=@new_default,matches=@new_default,matches-nothing=@all_same -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=regions-distinct=@into_default,regions-distinct=@new_default,matches-nothing=@all_same' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=matches=@all_same' -o /dev/null
// RUN: %differential %s %t.mlir
// BEFORE-DAG: expected regions-distinct: {{.*}}@into_default
// BEFORE-DAG: expected regions-distinct: {{.*}}@new_default
// BEFORE-DAG: expected matches-nothing: {{.*}}@all_same
// Identical regions merge: a case that does what the default does goes to
// the default, and without a default, cases that do the same become it.
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it, and @all_same, whose regions were one,
// matches nothing after it.

!C = !idr.data<"C", plain [@R(), @G(i64), @B()]>
idr.program @"match-merge" root(@root) stage(first) {
  idr.func @into_default(%n: i64, %x: i32) -> i32 {
    %r = idr.match_lit %n : i64 -> (i32) {
    case 0 {
      %c = arith.constant 7 : i32
      idr.yield %c : i32
    }
    case 1 {
      idr.yield %x : i32
    }
    case 2 {
      %c = arith.constant 7 : i32
      idr.yield %c : i32
    }
    default(%d: i64) {
      %c = arith.constant 7 : i32
      idr.yield %c : i32
    }
    }
    return %r : i32
  }

  // Without a default, two equal cases become it; a case that reads its
  // fields stays.
  idr.func @new_default(%c: !C, %x: i64) -> i64 {
    %r = idr.match %c : !C -> (i64) {
    case @R() {
      %s = arith.addi %x, %x : i64
      idr.yield %s : i64
    }
    case @G(%f: i64) {
      idr.yield %f : i64
    }
    case @B() {
      %s = arith.addi %x, %x : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }

  // When every region is the same, one is left and it is inlined.
  idr.func @all_same(%c: !C, %x: i64) -> i64 {
    %r = idr.match %c : !C -> (i64) {
    case @R() {
      %s = arith.muli %x, %x : i64
      idr.yield %s : i64
    }
    case @G(%unused: i64) {
      %s = arith.muli %x, %x : i64
      idr.yield %s : i64
    }
    default(%d: !C) {
      %s = arith.muli %x, %x : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  // The program's root runs every function above on what it reads: a
  // literal from 0 to 3 and a constructor of each kind by the byte's low
  // bits, and the rest of it as a number.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c2 = arith.constant 2 : i64
    %c3 = arith.constant 3 : i64
    %c4 = arith.constant 4 : i64
    %n = arith.remui %byte, %c4 : i64
    %k = arith.remui %byte, %c3 : i64
    %x = arith.shrui %byte, %c2 : i64
    %col = idr.match_lit %k : i64 -> (!C) {
    case 0 {
      %r = idr.con !C @R()
      idr.yield %r : !C
    }
    case 1 {
      %g = idr.con !C @G(%byte : i64)
      idr.yield %g : !C
    }
    default(%d: i64) {
      %b = idr.con !C @B()
      idr.yield %b : !C
    }
    }
    %r0 = idr.call @into_default(%n, %ch) : (i64, i32) -> i32
    %r0w = arith.extui %r0 : i32 to i64
    %w1 = idr.io.put_sint %r0w, %w0 : i64
    %r1 = idr.call @new_default(%col, %x) : (!C, i64) -> i64
    %w2 = idr.io.put_sint %r1, %w1 : i64
    %r2 = idr.call @all_same(%col, %x) : (!C, i64) -> i64
    %w3 = idr.io.put_sint %r2, %w2 : i64
    return %w3 : !idr.world
  }
}
