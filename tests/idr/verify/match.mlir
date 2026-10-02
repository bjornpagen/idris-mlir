// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics

idr.data @T {
  idr.ctor @A (i64)
  idr.ctor @B ()
}
func.func @f(%v: !idr.data<@T>) {
  // expected-error @+1 {{has two cases for @B}}
  idr.match %v : !idr.data<@T> -> () {
  case @B() {
    idr.yield
  }
  case @B() {
    idr.yield
  }
  }
  return
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%v: !idr.data<@T>) {
  // expected-error @+1 {{has a case for @C, which is not a constructor of '!idr.data<@T>'}}
  idr.match %v : !idr.data<@T> -> () {
  case @C() {
    idr.yield
  }
  }
  return
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%v: !idr.data<@T>) {
  // expected-error @+1 {{case @A must take the constructor's fields at the scrutinee's grade, 'i64'}}
  idr.match %v : !idr.data<@T> -> () {
  case @A(%x: i32) {
    idr.yield
  }
  }
  return
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%v: !idr.data<@T>) -> i64 {
  %r = idr.match %v : !idr.data<@T> -> (i64) {
  case @A(%x: i64) {
    %y = arith.trunci %x : i64 to i32
    // expected-error @+1 {{yields 'i32' but the match has results 'i64'}}
    idr.yield %y : i32
  }
  }
  return %r : i64
}

// -----

idr.data @T {
  idr.ctor @A (i64)
}
func.func @f(%v: !idr.data<@T>) {
  // expected-error @+1 {{region #0 must end in idr.yield or ub.unreachable}}
  idr.match %v : !idr.data<@T> -> () {
  case @A(%x: i64) {
    func.return
  }
  }
  return
}

// -----

func.func @f(%v: i64) {
  // expected-error @+1 {{expects one region per case and a default}}
  idr.match_lit %v : i64 -> () {
  case 0 {
    idr.yield
  }
  }
  return
}

// -----

func.func @f(%v: i64) {
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

// -----

func.func @f(%v: i8) {
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

// -----

func.func @f(%v: !idr.str) {
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

// -----

func.func @f(%v: f64) {
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

// -----

func.func @f() {
  // expected-error @+1 {{expects parent op to be one of 'idr.match, idr.match_lit, idr.array.generate, idr.array.fold'}}
  idr.yield
}
