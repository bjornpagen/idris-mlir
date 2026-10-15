// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=regions-distinct=@into_default,matches=@into_default,\
// RUN: regions-distinct=@new_default,matches=@new_default,matches-nothing=@all_same -o /dev/null
// RUN: idris-mlir-opt %s --idr-canonicalize=test-convergence=true -o /dev/null
// Identical regions merge: a case that does what the default does goes to
// the default, and without a default, cases that do the same become it.

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
    default {
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
    default {
      %s = arith.muli %x, %x : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
