// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics -o /dev/null
// What a cell holds it owns: in the owned stage a field that holds
// references takes an owned value of the field's type, whose reference
// moves into the cell, and never a borrow, which holds none.

!P = !idr.data<"P", plain [@P(!idr.str)]>
idr.program @"con-owned-field" root(@root) stage(owned) {
  idr.func @wrap(%s: !idr.own<!idr.str>) -> !idr.own<!P> {
    %p = idr.con !idr.own<!P> @P(%s : !idr.own<!idr.str>)
    return %p : !idr.own<!P>
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

!P = !idr.data<"P", plain [@P(!idr.str)]>
idr.program @"con-owned-field" root(@root) stage(owned) {
  idr.func @wrap(%s: !idr.own<!idr.str>) -> !idr.own<!P> {
    %v = idr.borrow %s : !idr.own<!idr.str>
    // expected-error @+1 {{field has type}}
    %p = idr.con !idr.own<!P> @P(%v : !idr.q<many, borrow, !idr.str>)
    idr.drop %s : !idr.own<!idr.str>
    return %p : !idr.own<!P>
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
