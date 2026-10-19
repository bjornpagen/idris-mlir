// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: sed '/^\/\/ -----/,$d' %s > %t.before.mlir
// RUN: idris-mlir-opt %t.before.mlir --idr-rc --idr-expect=holds=stage=owned -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 2' %s > %t.recycle.mlir
// RUN: idris-mlir-opt %t.recycle.mlir | idris-mlir-opt | FileCheck %s --check-prefix=RECYCLE
// The owned stage is the program's, said by its idr.program: idr-rc counts
// a program of the first stage and sets the owned one, and the verifier
// holds every function of the program to the stage's rules, whatever a
// function happens to hold. A function whose owned value is never consumed
// is refused. A box whose constructor has fields is built in its cell: a
// source gives the cell (here the cell of a token, recycled), which is
// owned, and idr.cell.init fills it, consuming it; each prints and parses
// back.
// RECYCLE-LABEL: idr.func @bump(
// RECYCLE: idr.take %{{.*}} : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
// RECYCLE: [[CELL:%[^ ]+]] = idr.cell.recycle %{{.*}} : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
// RECYCLE: idr.cell.init [[CELL]] : !idr.cell<!idr.box<!L>, @C> (%{{.*}} : i64, %{{.*}} : !idr.own<!idr.box<!L>>)
idr.program @"owned-stage" root(@Prog.main) stage(first) {
  idr.func @size(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
  idr.func @Prog.main() -> i64 {
    %a = idr.constant !idr.str "a"
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
      %c = idr.cell.recycle %w#0 : !idr.own<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
      %o = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%h2 : i64, %w#2 : !idr.own<!idr.box<!L>>)
      idr.yield %o : !idr.own<!idr.box<!L>>
    }
    default(%d: !idr.q<many, borrow, !idr.box<!L>>) {
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

// -----

// Past idr-rc a box whose constructor has fields is built in its cell, never
// as a value: an idr.con of it is refused.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"owned-stage" root(@Prog.main) stage(owned) {
  idr.func @cons(%x: i64, %t: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    // expected-error @+1 {{builds a box with fields as a value in the owned stage}}
    %l = idr.con !idr.own<!idr.box<!L>> @C(%x : i64, %t : !idr.own<!idr.box<!L>>)
    return %l : !idr.own<!idr.box<!L>>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A cell is filled exactly once: its type lets it be used once, and the
// owned stage counts it as the reference it is, which its init consumes.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"owned-stage" root(@Prog.main) stage(owned) {
  idr.func @unfilled() -> i64 {
    // expected-note @+1 {{the value is defined here}}
    %c = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    %z = arith.constant 0 : i64
    // expected-error @+1 {{returns while a value still holds a reference}}
    return %z : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A cell of the frame is lent to the box filled in it, which is therefore
// never exclusive.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"owned-stage" root(@Prog.main) stage(owned) {
  idr.func @frame(%x: i64, %t: !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>> {
    %c = idr.cell.stack : !idr.cell<!idr.box<!L>, @C>
    // expected-error @+1 {{builds an exclusive value in a cell of the frame, which is lent}}
    %b = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%x : i64, %t : !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
    return %b : !idr.excl<!idr.box<!L>>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// The nearest each refusal above has that verifies: the owned value
// dropped once read; the box built in a new cell; the cell filled, the
// box it gives dropped; and a box built in a cell of the frame owned, not
// exclusive, read and dropped.
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @"owned-stage" root(@Prog.main) stage(owned) {
  idr.func @noleak(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length borrow %v
    idr.drop %s : !idr.own<!idr.str>
    return %n : i64
  }
  idr.func @cons(%x: i64, %t: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %c = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    %l = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%x : i64, %t : !idr.own<!idr.box<!L>>)
    return %l : !idr.own<!idr.box<!L>>
  }
  idr.func @filled(%t: !idr.own<!idr.box<!L>>) -> i64 {
    %x = arith.constant 0 : i64
    %c = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    %l = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%x : i64, %t : !idr.own<!idr.box<!L>>)
    idr.drop %l : !idr.own<!idr.box<!L>>
    return %x : i64
  }
  idr.func @frame(%x: i64, %t: !idr.own<!idr.box<!L>>) -> i64 {
    %c = idr.cell.stack : !idr.cell<!idr.box<!L>, @C>
    %b = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%x : i64, %t : !idr.own<!idr.box<!L>>)
    %v = idr.borrow %b : !idr.own<!idr.box<!L>>
    %k = idr.tag %v : !idr.q<many, borrow, !idr.box<!L>>
    idr.drop %b : !idr.own<!idr.box<!L>>
    return %k : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
