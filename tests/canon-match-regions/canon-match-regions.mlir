// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// RUN: awk '/^\/\/ -----/ { n++; next } n == 3' %s > %t.exhaustive.mlir
// RUN: idris-mlir-opt %t.exhaustive.mlir --canonicalize=region-simplify=disabled \
// RUN: --idr-expect=holds=regions-distinct=@exhaustive,matches=@exhaustive,builds-nothing=@exhaustive,\
// RUN: reads-fields=@exhaustive -o /dev/null
// RUN: idris-mlir-opt %t.exhaustive.mlir '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %t.exhaustive.mlir --canonicalize=region-simplify=disabled -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.exhaustive.mlir --idr-expect=holds=regions-distinct=@exhaustive,builds-nothing=@exhaustive -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %differential %t.exhaustive.mlir %t.mlir
// BEFORE-DAG: expected regions-distinct: {{.*}} in @exhaustive
// BEFORE-DAG: expected builds-nothing: {{.*}} in @exhaustive
// A match's regions are the default's, then one per case. A default that
// runs binds the scrutinee back at its type, and is written once, after
// the cases.

idr.program @"match-regions" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%v: i64) {
    idr.match_lit %v : i64 -> () {
    case 0 {
      idr.yield
    }
    default(%d: i64) {
      idr.yield
    }
    // expected-error @-1 {{expected '}'}}
    default(%e: i64) {
      idr.yield
    }
    }
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T">
#types = #idr.types<
  "T" = plain [@A(i64), @B()]
>
idr.program @"match-regions" root(@root) stage(first) types #types {
  idr.func @f(%v: !T) {
    idr.match %v : !T -> () {
    case @A(%x: i64) {
      idr.yield
    }
    // expected-error @+1 {{expected '('}}
    default {
      idr.yield
    }
    }
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!T = !idr.data<"T">
#types = #idr.types<
  "T" = plain [@A(i64), @B()]
>
idr.program @"match-regions" root(@root) stage(first) types #types {
  idr.func @f(%v: !T) {
    // expected-error @+1 {{expects a default region that takes the scrutinee back at its type}}
    idr.match %v : !T -> () {
    case @A(%x: i64) {
      idr.yield
    }
    default(%d: i64) {
      idr.yield
    }
    }
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// An exhaustive match has an empty default. Its two equal cases become a
// default that binds the scrutinee back, and the field read of its result
// moves into its regions, where it meets the constructor it reads: what is
// left is one match of a case and a default, which reads a field of %p,
// and nothing is built; neither held before the pass. The root runs it
// on a constructor of each kind, and the program prints after the pass
// what it printed before, on every byte.
!C = !idr.data<"C">
!P = !idr.data<"P">
#types = #idr.types<
  "C" = plain [@R(), @G(i64), @B()],
  "P" = plain [@MkP(i64, i64)]
>
idr.program @"match-regions" root(@root) stage(first) types #types {
  idr.func @exhaustive(%c: !C, %p: !P) -> i64 {
    %q = idr.match %c : !C -> (!P) {
    case @R() {
      idr.yield %p : !P
    }
    case @G(%f: i64) {
      %one = arith.constant 1 : i64
      %made = idr.con !P @MkP(%f : i64, %one : i64)
      idr.yield %made : !P
    }
    case @B() {
      idr.yield %p : !P
    }
    }
    %first = idr.field %q : !P @MkP[0] -> i64
    return %first : i64
  }
  // The program's root runs @exhaustive on what it reads: a constructor
  // of each kind by the byte, and a pair of it.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %byte = arith.extui %ch : i32 to i64
    %c3 = arith.constant 3 : i64
    %c7 = arith.constant 7 : i64
    %k = arith.remui %byte, %c3 : i64
    %y = arith.addi %byte, %c7 : i64
    %c = idr.match_lit %k : i64 -> (!C) {
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
    %p = idr.con !P @MkP(%y : i64, %byte : i64)
    %r = idr.call @exhaustive(%c, %p) : (!C, !P) -> i64
    %w1 = idr.io.put_sint %r, %w0 : i64
    return %w1 : !idr.world
  }
}
