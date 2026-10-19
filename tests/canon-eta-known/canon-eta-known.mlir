// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=builds-nothing=@in_case,builds=@swapped,\
// RUN: builds=@wrong_case,reads-fields=@wrong_case,returns-argument=@singleton:0,builds-nothing=@singleton,\
// RUN: builds=@two_sources -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=builds-nothing=@in_case,returns-argument=@singleton:0,builds-nothing=@singleton' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=builds=@in_case' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=reads-fields=@in_case' -o /dev/null
// BEFORE-DAG: expected builds-nothing: {{.*}}@in_case
// BEFORE-DAG: expected returns-argument: {{.*}}@singleton
// BEFORE-DAG: expected builds-nothing: {{.*}}@singleton
// Record eta knows the constructor from the match that took the value
// apart, and from a type of one constructor; rebuilt in another
// constructor's case, from two values, or with its fields swapped, a
// constructor stays.
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it, and @in_case neither builds nor reads
// after it.

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
  // Writes a pair: its constructor's number, then its two fields.
  idr.func @put_pair(%p: !Pair, %w: !idr.world) -> !idr.world {
    %r = idr.match %p : !Pair -> (!idr.world) {
    case @Left(%a: i64, %b: i64) {
      %c = arith.constant 76 : i32
      %w1 = idr.io.put_char %c, %w
      %w2 = idr.io.put_sint %a, %w1 : i64
      %w3 = idr.io.put_sint %b, %w2 : i64
      idr.yield %w3 : !idr.world
    }
    case @Right(%a: i64, %b: i64) {
      %c = arith.constant 82 : i32
      %w1 = idr.io.put_char %c, %w
      %w2 = idr.io.put_sint %a, %w1 : i64
      %w3 = idr.io.put_sint %b, %w2 : i64
      idr.yield %w3 : !idr.world
    }
    }
    return %r : !idr.world
  }
  // The program's root runs every function above on a pair made from
  // what it reads: a Left or a Right by the byte's low bit. @wrong_case
  // reads a Left's fields of its value in its Right case, which only a
  // Left may give, so it is given Lefts alone.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c3 = arith.constant 3 : i64
    %bit = arith.andi %byte, %c1 : i64
    %a = arith.shrui %byte, %c1 : i64
    %b = arith.muli %a, %c3 : i64
    %left = idr.con !Pair @Left(%a : i64, %b : i64)
    %p = idr.match_lit %bit : i64 -> (!Pair) {
    case 0 {
      idr.yield %left : !Pair
    }
    default(%d: i64) {
      %right = idr.con !Pair @Right(%b : i64, %a : i64)
      idr.yield %right : !Pair
    }
    }
    %r0 = idr.call @in_case(%p) : (!Pair) -> !Pair
    %w1 = idr.call @put_pair(%r0, %w0) : (!Pair, !idr.world) -> !idr.world
    %r1 = idr.call @swapped(%p) : (!Pair) -> !Pair
    %w2 = idr.call @put_pair(%r1, %w1) : (!Pair, !idr.world) -> !idr.world
    %r2 = idr.call @wrong_case(%left) : (!Pair) -> !Pair
    %w3 = idr.call @put_pair(%r2, %w2) : (!Pair, !idr.world) -> !idr.world
    %r3 = idr.call @two_sources(%left, %p) : (!Pair, !Pair) -> !Pair
    %w4 = idr.call @put_pair(%r3, %w3) : (!Pair, !idr.world) -> !idr.world
    %o = idr.con !One @Only(%byte : i64)
    %r4 = idr.call @singleton(%o) : (!One) -> !One
    %f = idr.field %r4 : !One @Only[0] -> i64
    %w5 = idr.io.put_sint %f, %w4 : i64
    return %w5 : !idr.world
  }
}
