// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The owned stage's rule: every reference is consumed exactly once on every
// path, and nothing is used once its last reference is gone.

// A value that holds references and is consumed once on every path,
// borrowed where it is only read: accepted.
module attributes {idr.stage = "owned"} {
  func.func private @use(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    idr.dec %s : !idr.str
    return %n : i64
  }
  func.func private @twice(%s: !idr.str) -> (!idr.str, !idr.str) {
    idr.inc %s : !idr.str
    return %s, %s : !idr.str, !idr.str
  }
  func.func private @lend(%s: !idr.str {idr.borrowed}) -> !idr.str {
    %t = idr.str.append %s, %s
    return %t : !idr.str
  }
}

// -----

module attributes {idr.stage = "owned"} {
  // expected-note @+1 {{the value is defined here}}
  func.func private @twice(%s: !idr.str) -> (!idr.str, !idr.str) {
    // expected-error @+1 {{consumes a reference that the value does not hold here}}
    return %s, %s : !idr.str, !idr.str
  }
}

// -----

module attributes {idr.stage = "owned"} {
  // expected-note @+1 {{the value is defined here}}
  func.func private @leak(%s: !idr.str) -> i64 {
    %n = idr.str.length %s
    // expected-error @+1 {{returns while a value still holds a reference}}
    return %n : i64
  }
}

// -----

module attributes {idr.stage = "owned"} {
  // expected-note @+1 {{the value is defined here}}
  func.func private @late(%s: !idr.str) -> i64 {
    idr.dec %s : !idr.str
    // expected-error @+1 {{uses a value whose last reference is gone on this path}}
    %n = idr.str.length %s
    return %n : i64
  }
}

// -----

// A borrowed parameter holds no reference to give away.
module attributes {idr.stage = "owned"} {
  // expected-note @+1 {{the value is defined here}}
  func.func private @give(%s: !idr.str {idr.borrowed}) -> !idr.str {
    // expected-error @+1 {{consumes a reference that the value does not hold here}}
    return %s : !idr.str
  }
}

// -----

// The regions of a match are alternatives, and must agree where they meet.
module attributes {idr.stage = "owned"} {
  // expected-note @+1 {{the value is defined here}}
  func.func private @branch(%b: i1, %s: !idr.str) -> i64 {
    %z = arith.constant 0 : i64
    // expected-error @+1 {{leaves a value with 0 references on one path and 1 on another}}
    %r = idr.match_lit %b : i1 -> (i64) {
    case true {
      idr.dec %s : !idr.str
      idr.yield %z : i64
    }
    default {
      idr.yield %z : i64
    }
    }
    idr.dec %s : !idr.str
    return %r : i64
  }
}

// -----

// A field lives as long as the value it was read from, unless it takes a
// reference of its own.
module attributes {idr.stage = "owned"} {
  idr.data @P {
    idr.ctor @P (!idr.str)
  }
  func.func private @field(%p: !idr.data<@P>) -> !idr.str {
    %s = idr.field %p[@P, 0] : !idr.data<@P> -> !idr.str
    idr.inc %s : !idr.str
    idr.dec %p : !idr.data<@P>
    return %s : !idr.str
  }
}

// -----

module attributes {idr.stage = "owned"} {
  idr.data @P {
    idr.ctor @P (!idr.str)
  }
  func.func private @field(%p: !idr.data<@P>) -> i64 {
    // expected-note @+1 {{the value is defined here}}
    %s = idr.field %p[@P, 0] : !idr.data<@P> -> !idr.str
    idr.dec %p : !idr.data<@P>
    // expected-error @+1 {{uses a value whose last reference is gone on this path}}
    %n = idr.str.length %s
    return %n : i64
  }
}

// -----

// A reuse builds in a cell of its own size.
module attributes {idr.stage = "owned"} {
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i64, !idr.box<@L>)
    idr.ctor @One (i64)
  }
  func.func private @swap(%l: !idr.box<@L>) -> !idr.box<@L> {
    %r = idr.match %l : !idr.box<@L> -> (!idr.box<@L>) {
    case @C(%h: i64, %t: !idr.box<@L>) {
      %w:3 = idr.take %l @L::@C : !idr.box<@L> -> (!idr.token, i64, !idr.box<@L>)
      // expected-error @+1 {{builds a cell of 16 bytes in the 24-byte cell of @L::@C}}
      %o = idr.reuse %w#0 @L::@One(%w#1) : (i64) -> !idr.box<@L>
      idr.dec %w#2 : !idr.box<@L>
      idr.yield %o : !idr.box<@L>
    }
    default {
      idr.yield %l : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
}

// -----

// A take consumes its value and gives each field a reference of its own,
// which is then consumed once like any other.
module attributes {idr.stage = "owned"} {
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i64, !idr.box<@L>)
  }
  func.func private @head(%l: !idr.box<@L>) -> i64 {
    %r = idr.match %l : !idr.box<@L> -> (i64) {
    case @C(%h: i64, %t: !idr.box<@L>) {
      %w, %h2, %t2 = idr.take %l @L::@C : !idr.box<@L> -> (!idr.token, i64, !idr.box<@L>)
      idr.dec %w : !idr.token
      idr.dec %t2 : !idr.box<@L>
      idr.yield %h2 : i64
    }
    default {
      idr.dec %l : !idr.box<@L>
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
}

// -----

module attributes {idr.stage = "owned"} {
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i64, !idr.box<@L>)
  }
  func.func private @head(%l: !idr.box<@L>) -> i64 {
    %r = idr.match %l : !idr.box<@L> -> (i64) {
    case @C(%h: i64, %t: !idr.box<@L>) {
      // expected-note @+1 {{the value is defined here}}
      %w, %h2, %t2 = idr.take %l @L::@C : !idr.box<@L> -> (!idr.token, i64, !idr.box<@L>)
      idr.dec %w : !idr.token
      // expected-error @+1 {{ends a path on which a value still holds a reference}}
      idr.yield %h2 : i64
    }
    default {
      idr.dec %l : !idr.box<@L>
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
}
