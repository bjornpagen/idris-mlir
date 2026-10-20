// RUN: idris-mlir-opt %s --idr-expect=holds=counted-loop=@counted,counted-loop=@nested -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=counted-loop=@tested,counted-loop=@straight,counted-loop=@mixed -verify-diagnostics -o /dev/null
// A loop that counts to a bound with a step says its trip count (@counted,
// an scf.for); one that runs until its own test fails does not (@tested,
// an scf.while); and a function with no loop has none to count. Every loop
// must count: two counted ones, one in the other, hold (@nested), and a
// counted one beside one that tests fails, at the one that tests (@mixed).
idr.program @"counted-loop" root(@root) stage(first) types #idr.types<> {
  idr.func @counted(%n: index, %acc: i64) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %acc) -> (i64) {
      %x = arith.index_cast %i : index to i64
      %b = arith.addi %a, %x : i64
      scf.yield %b : i64
    }
    return %r : i64
  }
  idr.func @tested(%n: i64) -> i64 {
    // expected-error @below {{expected counted-loop: }}
    %r = scf.while (%x = %n) : (i64) -> i64 {
      %zero = arith.constant 0 : i64
      %more = arith.cmpi ne, %x, %zero : i64
      scf.condition(%more) %x : i64
    } do {
    ^bb0(%x: i64):
      %one = arith.constant 1 : i64
      %y = arith.subi %x, %one : i64
      scf.yield %y : i64
    }
    return %r : i64
  }
  // expected-error @below {{expected counted-loop: }}
  idr.func @straight(%x: i64) -> i64 {
    return %x : i64
  }
  idr.func @nested(%n: index, %acc: i64) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %acc) -> (i64) {
      %s = scf.for %j = %c0 to %i step %c1 iter_args(%b = %a) -> (i64) {
        %x = arith.index_cast %j : index to i64
        %c = arith.addi %b, %x : i64
        scf.yield %c : i64
      }
      scf.yield %s : i64
    }
    return %r : i64
  }
  idr.func @mixed(%n: index, %m: i64) -> (i64, i64) {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %z = arith.constant 0 : i64
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%a = %z) -> (i64) {
      %x = arith.index_cast %i : index to i64
      %b = arith.addi %a, %x : i64
      scf.yield %b : i64
    }
    // expected-error @below {{expected counted-loop: }}
    %t = scf.while (%x = %m) : (i64) -> i64 {
      %zero = arith.constant 0 : i64
      %more = arith.cmpi ne, %x, %zero : i64
      scf.condition(%more) %x : i64
    } do {
    ^bb0(%x: i64):
      %one = arith.constant 1 : i64
      %y = arith.subi %x, %one : i64
      scf.yield %y : i64
    }
    return %r, %t : i64, i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
