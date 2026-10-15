// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: sed '/^\/\/ -----/,$d' %s > %t.before.mlir
// RUN: idris-mlir-opt %t.before.mlir --idr-rc | FileCheck %s --implicit-check-not=stage
// RUN: awk '/^\/\/ -----/ { n++; next } n == 2' %s > %t.reuse.mlir
// RUN: idris-mlir-opt %t.reuse.mlir | idris-mlir-opt | FileCheck %s --check-prefix=REUSE
// The owned stage is what the grades say: a function with an owned value is
// in it, and its verifier keeps the stage's rule there, with no attribute
// to say so. idr-rc writes the grades and nothing else: its output names
// no stage. A function whose owned value is never consumed is refused; the
// program's root beside it, which holds no owned value, is not asked. A
// reuse, the owned stage's own constructor, prints and parses back with its
// token among its operands' types.
// CHECK: drop
// REUSE-LABEL: idr.func private @bump(
// REUSE: idr.take %{{.*}} @C : !idr.own<!idr.box<!L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
// REUSE: idr.reuse %{{.*}} @C(%{{.*}}, %{{.*}}) : (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>>
module {
  idr.func private @size(%s: !idr.str) -> i64 {
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

module {
  // expected-note @+1 {{the value is defined here}}
  idr.func private @leak(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length %v
    // expected-error @+1 {{returns while a value still holds a reference}}
    return %n : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

!L = !idr.data<"L", list [@N(), @C(i64, !idr.box<!idr.data<"L">>)]>
module {
  idr.func private @bump(%l: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.box<!L> -> (!idr.own<!idr.box<!L>>) {
    case @C(%h: i64, %t: !idr.box<!L>) {
      %w:3 = idr.take %l @C : !idr.own<!idr.box<!L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      %one = arith.constant 1 : i64
      %h2 = arith.addi %w#1, %one : i64
      %o = idr.reuse %w#0 @C(%h2, %w#2) : (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>>
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
