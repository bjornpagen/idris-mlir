// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: sed '/^\/\/ -----/,$d' %s > %t.before.mlir
// RUN: idris-mlir-opt %t.before.mlir --idr-rc --idr-expect=holds=stage=owned -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 2' %s > %t.reuse.mlir
// RUN: idris-mlir-opt %t.reuse.mlir | idris-mlir-opt | FileCheck %s --check-prefix=REUSE
// NEEDS-ACCEPTANCE: the printed form of idr.take and idr.reuse.
// NEEDS-ACCEPTANCE: idr-rc classifies values on the code each step sees (classes built per step): a field whose box's take moved its later uses may now be a view, one dup and drop fewer, if this fixture's output moves.
// The owned stage is the program's, said by its idr.program: idr-rc counts
// a program of the first stage and sets the owned one, and the verifier
// holds every function of the program to the stage's rules, whatever a
// function happens to hold. A function whose owned value is never consumed
// is refused. A reuse, the owned stage's own constructor, prints and
// parses back with the type it builds before the constructor.
// REUSE-LABEL: idr.func @bump(
// REUSE: idr.take %{{.*}} : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
// REUSE: idr.reuse %{{.*}} !idr.own<!idr.box<!L>> @C(%{{.*}} : i64, %{{.*}} : !idr.own<!idr.box<!L>>)
idr.program @"owned-stage" root(@Prog.main) stage(first) {
  idr.func @size(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
  idr.func @Prog.main() -> i64 {
    %a = idr.constant "a" : !idr.str
    %b = idr.str.append %a, %a
    %n = idr.call @size(%b) : (!idr.str) -> i64
    return %n : i64
  }
}

// -----

idr.program @"owned-stage" root(@Prog.main) stage(owned) {
  // expected-note @+1 {{the value is defined here}}
  idr.func @leak(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length borrow %v
    // expected-error @+1 {{returns while a value still holds a reference}}
    return %n : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"owned-stage" root(@Prog.main) stage(owned) {
  idr.func @bump(%l: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.q<many, borrow, !idr.box<!L>> -> (!idr.own<!idr.box<!L>>) {
    case @C(%h: i64, %t: !idr.q<many, borrow, !idr.box<!L>>) {
      %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      %one = arith.constant 1 : i64
      %h2 = arith.addi %w#1, %one : i64
      %o = idr.reuse %w#0 !idr.own<!idr.box<!L>> @C(%h2 : i64, %w#2 : !idr.own<!idr.box<!L>>)
      idr.yield %o : !idr.own<!idr.box<!L>>
    }
    default {
      idr.yield %l : !idr.own<!idr.box<!L>>
    }
    }
    return %r : !idr.own<!idr.box<!L>>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
