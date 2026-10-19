// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=forces=@knot,never-calls=@knot:@knot,\
// RUN: forces=@mid,never-calls=@mid:@label,forces=@other,never-calls=@other:@leaf -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir -c %t.mlir -o %t.o
// RUN: %cc %t.o -o %t.exe
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=forces=@label' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=never-calls=@label:@mid' -o /dev/null
// RUN: echo -n 0 | %t.exe > %t.other.out
// RUN: FileCheck %s --check-prefix=OTHER < %t.other.out
// RUN: echo -n 1 | %status 1 %t.exe 2> %t.knot.err
// RUN: FileCheck %s --check-prefix=KNOT < %t.knot.err
// RUN: echo -n 2 | %status 1 %t.exe 2> %t.mid.err
// RUN: FileCheck %s --check-prefix=KNOT < %t.mid.err
// OTHER: {{^7$}}
// KNOT: {{^idris-mlir: a suspension forced itself}}
// A constant suspension is one cell in static data, whose force runs its
// label once. Every force of it stays a force: a call of the label in its
// place would run the label again at each force, and in a knot (the
// label's own constant, or one a function it calls holds) would recurse
// where the cell's running state ends the program. So canonicalize leaves
// every force of a constant, whatever the label reaches.
// The root runs one of them by the byte it reads, and the program prints
// after canonicalize what it printed before, on every byte. Run, @other
// gives 7, and @knot and @label each end the program at the force that
// meets its own running cell, with the crash that names it. @label forces
// nothing and calls @mid, which the checks of it fail on.

// The label forces its own constant.
idr.program @"force-of-own-constant" root(@root) stage(higher) {
  idr.func @knot() -> i64 {
    %c = idr.constant !idr.lazy<i64> #idr.closure<@knot, []>
    %v = idr.force %c : !idr.lazy<i64> -> i64
    %one = arith.constant 1 : i64
    %r = arith.addi %v, %one : i64
    return %r : i64
  }

  // The label calls the function that forces its constant.
  idr.func @label() -> i64 {
    %r = idr.call @mid() : () -> i64
    return %r : i64
  }
  idr.func @mid() -> i64 {
    %c = idr.constant !idr.lazy<i64> #idr.closure<@label, []>
    %v = idr.force %c : !idr.lazy<i64> -> i64
    return %v : i64
  }

  // The label reaches nothing that holds its constant.
  idr.func @leaf() -> i64 attributes {total} {
    %c = arith.constant 7 : i64
    return %c : i64
  }
  idr.func @other() -> i64 {
    %c = idr.constant !idr.lazy<i64> #idr.closure<@leaf, []>
    %v = idr.force %c : !idr.lazy<i64> -> i64
    return %v : i64
  }

  // The program's root runs one of the functions that force a constant,
  // by the byte it reads: @other gives 7, and @knot and @label each force
  // their constant again while it runs, which ends the program.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c3 = arith.constant 3 : i64
    %sel = arith.remui %byte, %c3 : i64
    %r = idr.match_lit %sel : i64 -> (i64) {
    case 0 {
      %v = idr.call @other() : () -> i64
      idr.yield %v : i64
    }
    case 1 {
      %v = idr.call @knot() : () -> i64
      idr.yield %v : i64
    }
    default(%d: i64) {
      %v = idr.call @mid() : () -> i64
      idr.yield %v : i64
    }
    }
    %w1 = idr.io.put_sint %r, %w0 : i64
    return %w1 : !idr.world
  }
}
