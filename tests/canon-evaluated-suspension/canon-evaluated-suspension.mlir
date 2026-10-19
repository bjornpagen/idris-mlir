// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns-argument=@forced:0,forces-nothing=@forced,\
// RUN: builds=@forced_built,forces-nothing=@forced_built,forces-nothing=@computed,calls=@computed:@square -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=returns-argument=@forced:0,forces-nothing=@forced,forces-nothing=@forced_built,forces-nothing=@computed,calls=@computed:@square' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=builds=@forced' -o /dev/null
// BEFORE-DAG: expected returns-argument: {{.*}}@forced
// BEFORE-DAG: expected forces-nothing: {{.*}}@forced
// BEFORE-DAG: expected forces-nothing: {{.*}}@forced_built
// BEFORE-DAG: expected forces-nothing: {{.*}}@computed
// BEFORE-DAG: expected calls: @computed {{.*}}@square
// An evaluated suspension holds its value: `idr.delay %x`, whose operand is
// the value, with no region. Forcing it computes nothing, so a force of it
// folds to the value, a plain one or a cell built from values above it. A
// suspension that computes is a function of its own, which idr.suspend
// names; forced once and used nowhere else, it is a call of that function.
// The root runs every function on what it reads, and the program prints
// after canonicalize what it printed before, on every byte. What the pass
// makes hold did not hold before it, and @forced builds nothing after it.

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
  // The program's root runs every function above on what it reads.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %c7 = arith.constant 7 : i64
    %y = arith.subi %x, %c7 : i64
    %a = idr.call @forced(%x) : (i64) -> i64
    %w1 = idr.io.put_sint %a, %w0 : i64
    %p = idr.call @forced_built(%x, %y) : (i64, i64) -> !P
    %r = idr.match %p : !P -> (i64) {
    case @MkP(%u: i64, %v: i64) {
      %c100 = arith.constant 1000 : i64
      %s = arith.muli %u, %c100 : i64
      %t = arith.addi %s, %v : i64
      idr.yield %t : i64
    }
    }
    %w2 = idr.io.put_sint %r, %w1 : i64
    %b = idr.call @computed(%y) : (i64) -> i64
    %w3 = idr.io.put_sint %b, %w2 : i64
    return %w3 : !idr.world
  }
}
