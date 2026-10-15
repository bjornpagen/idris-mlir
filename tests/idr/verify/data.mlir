// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// NEEDS-ACCEPTANCE: the texts of a body's errors, as C01's setBody and type parser write them.
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
// expected-error @+1 {{has two constructors named @A}}
!T = !idr.data<"T", plain [@A(), @A()]>

// -----

// Only a memo sum's label is ever forced by name.
// expected-error @+1 {{by_name}}
!T = !idr.data<"T", plain [@A() by_name]>

// -----

// A memo sum ends in its two states: running, then forced with the value.
// expected-error @+1 {{running}}
!M = !idr.data<"M", memo [@f() running, @forced(i64) forced]>

// -----

// Base's list: nil, then a cons of an element and a box of the list.
// expected-error @+1 {{list}}
!L = !idr.data<"L", list [@Nil() nil, @Cons(i64) cons]>

// -----

// A body is set once: the same name with another body is refused.
!T = !idr.data<"T", plain [@A(i64)]>
// expected-error @+1 {{already has a body}}
!U = !idr.data<"T", plain [@B()]>

// -----

// The name alone is the type only inside its own body.
// expected-error @+1 {{a data type is written without its body only inside its own body}}
!T = !idr.data<"T">
