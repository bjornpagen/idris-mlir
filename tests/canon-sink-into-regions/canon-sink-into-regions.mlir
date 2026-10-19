// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-heap-allocation=@write_in_both,\
// RUN: checks-every-path=@may_crash -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=no-heap-allocation=@write_in_both' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=checks-every-path=@write_in_both' -o /dev/null
// RUN: %differential %s %t.mlir
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@write_in_both
// A value free of effects (an allocation aside) that only a match's regions
// use moves into each region that uses it; there it meets its consumer.
// One that may crash stays where it runs on every path.
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. With a divisor
// of 0 the guard crashes whichever region runs, as it did before. What the
// pass makes hold did not hold before it, and @write_in_both checks
// nothing.

// putStr (show x) in both regions of a match on b: the string moves into
// each region, where output fusion writes the number without building it.
!Bool = !idr.data<"Bool", plain [@False(), @True()]>
idr.program @"sink-into-regions" root(@root) stage(first) {
  idr.func @write_in_both(%b: !Bool, %x: i64, %w: !idr.world) -> !idr.world {
    %s = idr.str.show_sint %x : i64
    %r = idr.match %b : !Bool -> (!idr.world) {
    case @False() {
      %c = idr.constant !idr.str "no: "
      %w1 = idr.io.put_str %c, %w
      %w2 = idr.io.put_str %s, %w1
      idr.yield %w2 : !idr.world
    }
    case @True() {
      %c = idr.constant !idr.str "yes: "
      %w1 = idr.io.put_str %c, %w
      %w2 = idr.io.put_str %s, %w1
      idr.yield %w2 : !idr.world
    }
    }
    return %r : !idr.world
  }

  // A value with an effect (a guard, which may crash) stays before the match.
  idr.func @may_crash(%n: i64, %x: i64, %y: i64) -> i64 {
    %y1 = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %y1 : i64
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %q : i64
    }
    default(%d: i64) {
      idr.yield %n : i64
    }
    }
    return %r : i64
  }
  // The program's root runs both functions above on what it reads: the
  // byte's low bit chooses each, the byte less 128 is the number written,
  // and the rest of it the divisor, 0 for the bytes 0 and 1, where the
  // guard crashes whichever region runs.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c1 = arith.constant 1 : i64
    %c128 = arith.constant 128 : i64
    %bit = arith.andi %byte, %c1 : i64
    %x = arith.subi %byte, %c128 : i64
    %y = arith.shrui %byte, %c1 : i64
    %b = idr.match_lit %bit : i64 -> (!Bool) {
    case 0 {
      %f = idr.con !Bool @False()
      idr.yield %f : !Bool
    }
    default(%d: i64) {
      %t = idr.con !Bool @True()
      idr.yield %t : !Bool
    }
    }
    %w1 = idr.call @write_in_both(%b, %x, %w0) : (!Bool, i64, !idr.world) -> !idr.world
    %r = idr.call @may_crash(%bit, %x, %y) : (i64, i64, i64) -> i64
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
