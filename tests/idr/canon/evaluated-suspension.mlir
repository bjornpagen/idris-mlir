// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns-argument=@forced:0,forces-nothing=@forced,\
// RUN: builds=@forced_built,forces-nothing=@forced_built,forces-nothing=@computed,calls=@computed:@square -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize=test-convergence=true -o /dev/null
// An evaluated suspension holds its value: `idr.delay %x`, whose operand is
// the value, with no region. Forcing it computes nothing, so a force of it
// folds to the value, a plain one or a cell built from values above it. A
// suspension that computes is a function of its own, which idr.suspend
// names; forced once and used nowhere else, it is a call of that function.

!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.program @"evaluated-suspension" root(@root) stage(higher) {
  idr.func @forced(%x: i64) -> i64 {
    %t = idr.delay %x : i64 -> !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }

  idr.func @forced_built(%x: i64, %y: i64) -> !P {
    %p = idr.con !P @MkP(%x : i64, %y : i64)
    %t = idr.delay %p : !P -> !idr.lazy<!P>
    %v = idr.force %t : !idr.lazy<!P> -> !P
    return %v : !P
  }

  idr.func @square(%x: i64) -> i64 attributes {total} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }

  idr.func @computed(%x: i64) -> i64 {
    %t = idr.suspend @square(%x) : (i64) -> !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
