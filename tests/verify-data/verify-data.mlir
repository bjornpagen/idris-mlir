// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A data type is identified by its name and carries its body, its
// constructors in tag order, set once: a body that breaks a rule of its
// kind is refused where the type is written, and so is a second body for
// a name that has one.

// A field's quantity is its type: linear fields are !idr.lin.
!T = !idr.data<"T", plain [@A(!idr.lin<i64>, i64)]>
idr.program @data root(@root) stage(first) {
  idr.func @f(%t: !T) -> !T {
    return %t : !T
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// expected-error @+1 {{expects a grade of a plain type, got one of '!idr.lin<i64>'}}
!T = !idr.data<"T", plain [@A(!idr.lin<!idr.lin<i64>>)]>

// -----

// expected-error @+1 {{has a field of unsupported type 'f32'}}
!T = !idr.data<"T", plain [@A(f32)]>

// -----

// expected-error @+1 {{has a field of unsupported type 'i1'}}
!T = !idr.data<"T", plain [@A(i1)]>

// -----

// expected-error @+1 {{has a field of unsupported type 'index'}}
!T = !idr.data<"T", plain [@A(index)]>

// -----

// Constructor names are distinct: a tag is a position, a name its key.
// expected-error @+1 {{has two constructors @A}}
!T = !idr.data<"T", plain [@A(), @A()]>


// -----

// Base's list: nil, then a cons of an element and a box of the list.
// expected-error @+1 {{list}}
!L = !idr.data<"L", list [@Nil() nil, @Cons(i64) cons]>

// -----

// A body is set once: the same name with another body is refused.
!T = !idr.data<"T", plain [@A(i64)]>
// expected-error @+1 {{has another body already}}
!U = !idr.data<"T", plain [@B()]>

// -----

// The name alone is the type only inside its own body.
// expected-error @+1 {{a data type is written without its body only inside its own body}}
!T = !idr.data<"T">

// -----

// The nearest each refusal above has that verifies: a linear field of a
// plain type; fields of the widths a field may have, f64, i8 and i64;
// two constructors of two names; base's list, its cons holding a box of the
// list, the type written without its body inside its body; and the same
// body written twice for one name, which is one type.
!T = !idr.data<"T", plain [@A(!idr.lin<i64>), @B(f64, i8, i64)]>
!L = !idr.data<"L", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"L">>) cons]>
!U = !idr.data<"U", plain [@A(i64)]>
!V = !idr.data<"U", plain [@A(i64)]>
idr.program @data root(@root) stage(first) {
  idr.func @f(%t: !T, %l: !idr.box<!L>, %u: !U) -> (!T, !idr.box<!L>, !V) {
    return %t, %l, %u : !T, !idr.box<!L>, !V
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
