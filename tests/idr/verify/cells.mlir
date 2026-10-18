// NEEDS-ACCEPTANCE: that a recycle of an exclusive token and the init of an exclusive box print and parse back (RUN 2-3); that each split below is refused as its expected-error says, the hole at an i64 field in a release build too.
// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// RUN: sed '/^\/\/ -----/,$d' %s > %t.exclusive.mlir
// RUN: idris-mlir-opt %t.exclusive.mlir | idris-mlir-opt | FileCheck %s
// A box's constructor is built in a cell idr-rc makes explicit: the cell's
// source writes its header (here idr.cell.recycle, the cell of an exclusive
// token, which is the cell for certain) and idr.cell.init its fields,
// giving the box at the grade counting proved. Only a constructor with
// fields has a cell, and only a box's field is a hole. A value whose
// constructor has a cell is taken apart by idr.take, any other by
// idr.unpack, each with the results its operand's type and constructor say.
// CHECK-LABEL: idr.func @exclusive(
// CHECK: idr.take %{{.*}} : !idr.excl<!idr.box<!L>> @C -> (!idr.excl<!idr.token>, i64, !idr.excl<!idr.box<!L>>)
// CHECK: [[CELL:%[^ ]+]] = idr.cell.recycle %{{.*}} : !idr.excl<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
// CHECK: idr.cell.init [[CELL]] : !idr.cell<!idr.box<!L>, @C> (%{{.*}} : i64, %{{.*}} : !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @cells root(@root) stage(owned) {
  idr.func @exclusive(%l: !idr.excl<!idr.box<!L>>, %x: i64) -> !idr.excl<!idr.box<!L>> {
    %w:3 = idr.take %l : !idr.excl<!idr.box<!L>> @C -> (!idr.excl<!idr.token>, i64, !idr.excl<!idr.box<!L>>)
    %c = idr.cell.recycle %w#0 : !idr.excl<!idr.token> -> !idr.cell<!idr.box<!L>, @C>
    %b = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%x : i64, %w#2 : !idr.excl<!idr.box<!L>>) -> !idr.excl<!idr.box<!L>>
    return %b : !idr.excl<!idr.box<!L>>
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @cells root(@root) stage(owned) {
  idr.func @root() -> i64 {
    // expected-error @+1 {{is a cell of @N, an atom of "L", which has no cell}}
    %c = idr.cell.new : !idr.cell<!idr.box<!L>, @N>
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @cells root(@root) stage(owned) {
  idr.func @wrong(%t: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %x = arith.constant 1 : i32
    %c = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    // expected-error @+1 {{its fields are its cell's constructor's, the holes aside}}
    %b = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (%x : i32, %t : !idr.own<!idr.box<!L>>)
    return %b : !idr.own<!idr.box<!L>>
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @cells root(@root) stage(owned) {
  idr.func @hole(%t: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %c = idr.cell.new : !idr.cell<!idr.box<!L>, @C>
    // expected-error @+2 {{has a hole at field 0 of type i64, which is no box: only a box's field is written through a destination}}
    // expected-error @+1 {{failed to infer returned types}}
    %b = idr.cell.init %c : !idr.cell<!idr.box<!L>, @C> (dest, %t : !idr.own<!idr.box<!L>>)
    return %b : !idr.own<!idr.box<!L>>
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!S = !idr.data<"S", plain [@A(i64, !idr.str), @B()]>
idr.program @cells root(@root) stage(owned) {
  idr.func @take(%s: !idr.own<!S>) -> i64 {
    // expected-error @+2 {{which has none: idr.unpack takes it apart}}
    // expected-error @+1 {{failed to infer returned types}}
    %w:3 = idr.take %s : !idr.own<!S> @A -> (!idr.own<!idr.token>, i64, !idr.own<!idr.str>)
    idr.drop %w#0 : !idr.own<!idr.token>
    idr.drop %w#2 : !idr.own<!idr.str>
    return %w#1 : i64
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @cells root(@root) stage(owned) {
  idr.func @unpack(%l: !idr.own<!idr.box<!L>>) -> i64 {
    // expected-error @+2 {{which has a cell: idr.take takes it apart}}
    // expected-error @+1 {{failed to infer returned types}}
    %f:2 = idr.unpack %l : !idr.own<!idr.box<!L>> @C -> (i64, !idr.own<!idr.box<!L>>)
    idr.drop %f#1 : !idr.own<!idr.box<!L>>
    return %f#0 : i64
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!L = !idr.data<"L", list [@N() nil, @C(i64, !idr.box<!idr.data<"L">>) cons]>
idr.program @cells root(@root) stage(owned) {
  idr.func @mistyped(%l: !idr.own<!idr.box<!L>>) -> i64 {
    // expected-error @+2 {{are incompatible with return type(s) of operation}}
    // expected-error @+1 {{failed to infer returned types}}
    %w:3 = idr.take %l : !idr.own<!idr.box<!L>> @C -> (!idr.own<!idr.token>, i64, !idr.box<!L>)
    idr.drop %w#0 : !idr.own<!idr.token>
    return %w#1 : i64
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
