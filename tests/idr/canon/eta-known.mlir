// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=builds-nothing=@in_case,builds=@swapped,\
// RUN: builds=@wrong_case,reads-fields=@wrong_case,returns-argument=@singleton:0,builds-nothing=@singleton,\
// RUN: builds=@two_sources -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// Record eta knows the constructor from the match that took the value
// apart, and from a type of one constructor; rebuilt in another
// constructor's case, from two values, or with its fields swapped, a
// constructor stays.

// In the case that matched it, a value rebuilt from the case's reads of it
// is the value; with the fields swapped it is a new one.
!Pair = !idr.data<"Pair", plain [@Left(i64, i64), @Right(i64, i64)]>
!One = !idr.data<"One", plain [@Only(i64)]>
idr.program @"eta-known" root(@root) stage(first) {
  idr.func @in_case(%p: !Pair) -> !Pair {
    %r = idr.match %p : !Pair -> (!Pair) {
    case @Left(%a: i64, %b: i64) {
      %x = idr.field %p : !Pair @Left[0] -> i64
      %y = idr.field %p : !Pair @Left[1] -> i64
      %c = idr.con !Pair @Left(%x : i64, %y : i64)
      idr.yield %c : !Pair
    }
    case @Right(%a: i64, %b: i64) {
      idr.yield %p : !Pair
    }
    }
    return %r : !Pair
  }
  idr.func @swapped(%p: !Pair) -> !Pair {
    %r = idr.match %p : !Pair -> (!Pair) {
    case @Left(%a: i64, %b: i64) {
      %c = idr.con !Pair @Left(%b : i64, %a : i64)
      idr.yield %c : !Pair
    }
    case @Right(%a: i64, %b: i64) {
      idr.yield %p : !Pair
    }
    }
    return %r : !Pair
  }

  // In the other constructor's case the value is not known to be what the
  // rebuild builds, and the type has another constructor: it stays.
  idr.func @wrong_case(%p: !Pair) -> !Pair {
    %r = idr.match %p : !Pair -> (!Pair) {
    case @Left(%a: i64, %b: i64) {
      idr.yield %p : !Pair
    }
    case @Right(%a: i64, %b: i64) {
      %x = idr.field %p : !Pair @Left[0] -> i64
      %y = idr.field %p : !Pair @Left[1] -> i64
      %c = idr.con !Pair @Left(%x : i64, %y : i64)
      idr.yield %c : !Pair
    }
    }
    return %r : !Pair
  }

  // A type of one constructor needs no match: the value is that constructor.
  idr.func @singleton(%o: !One) -> !One {
    %f = idr.field %o : !One @Only[0] -> i64
    %c = idr.con !One @Only(%f : i64)
    return %c : !One
  }

  // Fields read from two values rebuild neither.
  idr.func @two_sources(%p: !Pair, %q: !Pair) -> !Pair {
    %x = idr.field %p : !Pair @Left[0] -> i64
    %y = idr.field %q : !Pair @Left[1] -> i64
    %c = idr.con !Pair @Left(%x : i64, %y : i64)
    return %c : !Pair
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
