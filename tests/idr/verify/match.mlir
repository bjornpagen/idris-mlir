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
    // expected-error-re @+1 {{has a case for @C, which is not a constructor of '!idr.data<"T"{{.*}}>'}}
    idr.match %v : !T -> () {
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
  idr.func @f(%v: !T) -> i64 {
    // expected-error @+1 {{along control flow edge from Operation idr.yield to Operation idr.match: successor operand type #0 'i32' should match successor input type #0 'i64'}}
    %r = idr.match %v : !T -> (i64) {
    case @A(%x: i64) {
      %y = arith.trunci %x : i64 to i32
      // expected-note @+1 {{region branch point}}
      idr.yield %y : i32
    }
    }
    return %r : i64
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
    // expected-error @+1 {{region #0 must end in idr.yield or ub.unreachable}}
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
    // expected-error @+1 {{expects one region per case and a default}}
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

idr.program @match root(@root) stage(first) {
  idr.func @f(%v: i8) {
    idr.match_lit %v : i8 -> () {
    // expected-error @+1 {{key does not fit in 'i8'}}
    case 256 {
      idr.yield
    }
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

idr.program @match root(@root) stage(first) {
  idr.func @f(%v: f64) {
    idr.match_lit %v : f64 -> () {
    // expected-error @+1 {{a literal match on 'f64' has no keys}}
    case 1 {
      idr.yield
    }
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
