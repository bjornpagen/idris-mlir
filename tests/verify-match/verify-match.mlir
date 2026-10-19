// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

!T = !idr.data<"T", plain [@A(i64), @B()]>
idr.program @match root(@root) stage(first) {
  idr.func @f(%v: !T) {
    // expected-error @+1 {{has two cases for @B}}
    idr.match %v : !T -> () {
    case @B() {
      idr.yield
    }
    case @B() {
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

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @match root(@root) stage(first) {
  idr.func @f(%v: !T) {
    idr.match %v : !T -> () {
    // expected-error @+1 {{the data type "T" has no constructor @C}}
    case @C() {
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

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @match root(@root) stage(first) {
  idr.func @f(%v: !T) {
    // expected-error @+1 {{case @A must take the constructor's fields at the scrutinee's grade, 'i64'}}
    idr.match %v : !T -> () {
    case @A(%x: i32) {
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

!T = !idr.data<"T", plain [@A(i64)]>
idr.program @match root(@root) stage(first) {
  idr.func @f(%v: !T) {
    // expected-error @+1 {{region #1 must end in idr.yield or ub.unreachable}}
    idr.match %v : !T -> () {
    case @A(%x: i64) {
      llvm.unreachable
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

idr.program @match root(@root) stage(first) {
  idr.func @f(%v: i64) {
    // expected-error @+1 {{region #0 ('defaultRegion') failed to verify constraint: region with 1 blocks}}
    idr.match_lit %v : i64 -> () {
    case 0 {
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

idr.program @match root(@root) stage(first) {
  idr.func @f(%v: i64) {
    // expected-error @+1 {{has two cases for 1 : i64}}
    idr.match_lit %v : i64 -> () {
    case 1 {
      idr.yield
    }
    case 1 {
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

idr.program @match root(@root) stage(first) {
  idr.func @f(%v: i8) {
    idr.match_lit %v : i8 -> () {
    // expected-error @+1 {{key does not fit in 'i8'}}
    case 256 {
      idr.yield
    }
    default(%d: i8) {
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

idr.program @match root(@root) stage(first) {
  idr.func @f(%v: !idr.str) {
    // expected-error @+1 {{has two cases for "a"}}
    idr.match_lit %v : !idr.str -> () {
    case "a" {
      idr.yield
    }
    case "a" {
      idr.yield
    }
    default(%d: !idr.str) {
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

idr.program @match root(@root) stage(first) {
  idr.func @f(%v: f64) {
    idr.match_lit %v : f64 -> () {
    // expected-error @+1 {{a literal match on 'f64' has no keys}}
    case 1 {
      idr.yield
    }
    default(%d: f64) {
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

idr.program @match root(@root) stage(first) {
  idr.func @f() {
    // expected-error @+1 {{expects parent op to be one of 'idr.match, idr.match_lit'}}
    idr.yield
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
