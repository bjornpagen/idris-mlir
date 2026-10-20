// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A call of a function by name passes what its callee takes and expects
// what it returns, each type its parameter's or result's, grade included:
// so what a call takes over is read from its operands' types, with no look
// at its callee. The callee is read once per verify of the module. A
// return gives its function's results. Each mismatch is named by its
// position, the first argument or a later one, by count, too many or none,
// and by grade at the owned stage: a borrow where the callee takes the
// value owned.

idr.program @"call-type" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
  idr.func @g(%s: !idr.str) -> i64 {
    %r = idr.call @f(%s) : (!idr.str) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"call-type" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
  idr.func @g(%x: i64) -> i64 {
    // expected-error @+1 {{passes 'i64' as argument 0 of @f, which takes '!idr.str'}}
    %r = idr.call @f(%x) : (i64) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"call-type" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
  idr.func @g(%s: !idr.str) -> i64 {
    // expected-error @+1 {{passes 2 arguments to @f, which takes 1}}
    %r = idr.call @f(%s, %s) : (!idr.str, !idr.str) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"call-type" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%s: !idr.str) -> !idr.str {
    return %s : !idr.str
  }
  idr.func @g(%s: !idr.str) -> i64 {
    // expected-error @+1 {{expects 'i64' as result 0 of @f, which returns '!idr.str'}}
    %r = idr.call @f(%s) : (!idr.str) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"call-type" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
  idr.func @g(%s: !idr.str) -> i64 {
    // expected-error @+1 {{expects 2 results from @f, which returns 1}}
    %r:2 = idr.call @f(%s) : (!idr.str) -> (i64, i64)
    return %r#0 : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"call-type" root(@root) stage(first) types #idr.types<> {
  idr.func @h(%x: i64) -> i64 {
    // expected-error @+1 {{calls @g}}
    %r = idr.call @g(%x) : (i64) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"call-type" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    // expected-error @+1 {{returns 2 values, but @f returns 1}}
    return %n, %n : i64, i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"call-type" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%s: !idr.str) -> !idr.str {
    %n = idr.str.length %s
    // expected-error @+1 {{returns 'i64' as result 0, but @f returns '!idr.str'}}
    return %n : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"call-type" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%x: i64, %s: !idr.str) -> i64 {
    return %x : i64
  }
  idr.func @g(%x: i64) -> i64 {
    // expected-error @+1 {{passes 'i64' as argument 1 of @f, which takes '!idr.str'}}
    %r = idr.call @f(%x, %x) : (i64, i64) -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"call-type" root(@root) stage(first) types #idr.types<> {
  idr.func @f(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    return %n : i64
  }
  idr.func @g() -> i64 {
    // expected-error @+1 {{passes 0 arguments to @f, which takes 1}}
    %r = idr.call @f() : () -> i64
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

idr.program @"call-type" root(@root) stage(owned) types #idr.types<> {
  idr.func @f(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length borrow %v
    idr.drop %s : !idr.own<!idr.str>
    return %n : i64
  }
  idr.func @g(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    // expected-error @+1 {{passes '!idr.q<many, borrow, !idr.str>' as argument 0 of @f, which takes '!idr.own<!idr.str>'}}
    %r = idr.call @f(%v) : (!idr.q<many, borrow, !idr.str>) -> i64
    idr.drop %s : !idr.own<!idr.str>
    return %r : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
