// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The owned stage's rule: every reference is consumed exactly once on every
// path, and nothing is used once its last reference is gone. The grades say
// what each value holds: `!idr.own<T>` one reference of its own, plain T
// (a view) none.

// A value that holds references and is consumed once on every path, read
// through views where it is only read: accepted.
module attributes {idr.stage = "owned"} {
  func.func private @use(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length %v
    idr.drop %s : !idr.own<!idr.str>
    return %n : i64
  }
  func.func private @twice(%s: !idr.own<!idr.str>) -> (!idr.own<!idr.str>, !idr.own<!idr.str>) {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %t = idr.dup %v : !idr.str
    return %s, %t : !idr.own<!idr.str>, !idr.own<!idr.str>
  }
  func.func private @lend(%s: !idr.str) -> !idr.own<!idr.str> {
    %t = idr.str.append %s, %s : !idr.own<!idr.str>
    return %t : !idr.own<!idr.str>
  }
}

// -----

module attributes {idr.stage = "owned"} {
  // expected-note @+1 {{the value is defined here}}
  func.func private @twice(%s: !idr.own<!idr.str>) -> (!idr.own<!idr.str>, !idr.own<!idr.str>) {
    // expected-error @+1 {{consumes a reference that the value does not hold here}}
    return %s, %s : !idr.own<!idr.str>, !idr.own<!idr.str>
  }
}

// -----

module attributes {idr.stage = "owned"} {
  // expected-note @+1 {{the value is defined here}}
  func.func private @leak(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length %v
    // expected-error @+1 {{returns while a value still holds a reference}}
    return %n : i64
  }
}

// -----

module attributes {idr.stage = "owned"} {
  // expected-note @+1 {{the value is defined here}}
  func.func private @late(%s: !idr.own<!idr.str>) -> i64 {
    idr.drop %s : !idr.own<!idr.str>
    // expected-error @+1 {{uses a value whose last reference is gone on this path}}
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length %v
    return %n : i64
  }
}

// -----

// A view holds no reference to give away: a consuming position (a field
// of a constructor) takes a reference of its own, never a view. (An owned
// value read directly is a type error already: the reading ops take plain
// values.)
module attributes {idr.stage = "owned"} {
  idr.data @P {
    idr.ctor @P (!idr.str)
  }
  // expected-note @+1 {{the value is defined here}}
  func.func private @give(%s: !idr.str) -> !idr.own<!idr.data<@P>> {
    // expected-error @+1 {{consumes a view, which holds no reference}}
    %p = idr.con @P::@P(%s) : (!idr.str) -> !idr.own<!idr.data<@P>>
    return %p : !idr.own<!idr.data<@P>>
  }
}

// -----

// The regions of a match are alternatives, and must agree where they meet.
module attributes {idr.stage = "owned"} {
  // expected-note @+1 {{the value is defined here}}
  func.func private @branch(%b: i1, %s: !idr.own<!idr.str>) -> i64 {
    %z = arith.constant 0 : i64
    // expected-error @+1 {{leaves a value with 0 references on one path and 1 on another}}
    %r = idr.match_lit %b : i1 -> (i64) {
    case true {
      idr.drop %s : !idr.own<!idr.str>
      idr.yield %z : i64
    }
    default {
      idr.yield %z : i64
    }
    }
    idr.drop %s : !idr.own<!idr.str>
    return %r : i64
  }
}

// -----

// A field is a view that lives as long as the value it was read from,
// unless it takes a reference of its own.
module attributes {idr.stage = "owned"} {
  idr.data @P {
    idr.ctor @P (!idr.str)
  }
  func.func private @field(%p: !idr.own<!idr.data<@P>>) -> !idr.own<!idr.str> {
    %v = idr.borrow %p : !idr.own<!idr.data<@P>>
    %s = idr.field %v[@P, 0] : !idr.data<@P> -> !idr.str
    %t = idr.dup %s : !idr.str
    idr.drop %p : !idr.own<!idr.data<@P>>
    return %t : !idr.own<!idr.str>
  }
}

// -----

module attributes {idr.stage = "owned"} {
  idr.data @P {
    idr.ctor @P (!idr.str)
  }
  func.func private @field(%p: !idr.own<!idr.data<@P>>) -> i64 {
    %v = idr.borrow %p : !idr.own<!idr.data<@P>>
    // expected-note @+1 {{the value is defined here}}
    %s = idr.field %v[@P, 0] : !idr.data<@P> -> !idr.str
    idr.drop %p : !idr.own<!idr.data<@P>>
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
  func.func private @swap(%l: !idr.own<!idr.box<@L>>) -> !idr.own<!idr.box<@L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<@L>>
    %r = idr.match %v : !idr.box<@L> -> (!idr.own<!idr.box<@L>>) {
    case @C(%h: i64, %t: !idr.box<@L>) {
      %w:3 = idr.take %l @L::@C : !idr.own<!idr.box<@L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<@L>>)
      // expected-error @+1 {{builds a cell of 16 bytes in the 24-byte cell of @L::@C}}
      %o = idr.reuse %w#0 @L::@One(%w#1) : (!idr.own<!idr.token>, i64) -> !idr.own<!idr.box<@L>>
      idr.drop %w#2 : !idr.own<!idr.box<@L>>
      idr.yield %o : !idr.own<!idr.box<@L>>
    }
    default {
      idr.yield %l : !idr.own<!idr.box<@L>>
    }
    }
    return %r : !idr.own<!idr.box<@L>>
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
  func.func private @head(%l: !idr.own<!idr.box<@L>>) -> i64 {
    %v = idr.borrow %l : !idr.own<!idr.box<@L>>
    %r = idr.match %v : !idr.box<@L> -> (i64) {
    case @C(%h: i64, %t: !idr.box<@L>) {
      %w, %h2, %t2 = idr.take %l @L::@C : !idr.own<!idr.box<@L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<@L>>)
      idr.drop %w : !idr.own<!idr.token>
      idr.drop %t2 : !idr.own<!idr.box<@L>>
      idr.yield %h2 : i64
    }
    default {
      idr.drop %l : !idr.own<!idr.box<@L>>
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
  func.func private @head(%l: !idr.own<!idr.box<@L>>) -> i64 {
    %v = idr.borrow %l : !idr.own<!idr.box<@L>>
    %r = idr.match %v : !idr.box<@L> -> (i64) {
    case @C(%h: i64, %t: !idr.box<@L>) {
      // expected-note @+1 {{the value is defined here}}
      %w, %h2, %t2 = idr.take %l @L::@C : !idr.own<!idr.box<@L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<@L>>)
      idr.drop %w : !idr.own<!idr.token>
      // expected-error @+1 {{ends a path on which a value still holds a reference}}
      idr.yield %h2 : i64
    }
    default {
      idr.drop %l : !idr.own<!idr.box<@L>>
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
}

// -----

// A string builder walks the cells of its list, a view, so it is refused
// once the reference the view borrows is gone, as a field read is.
module attributes {idr.stage = "owned"} {
  idr.data @Chars box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i32, !idr.box<@Chars>)
  }
  func.func private @pack(%l: !idr.own<!idr.box<@Chars>>) -> !idr.own<!idr.str> {
    // expected-note @+1 {{the value is defined here}}
    %v = idr.borrow %l : !idr.own<!idr.box<@Chars>>
    idr.drop %l : !idr.own<!idr.box<@Chars>>
    // expected-error @+1 {{uses a value whose last reference is gone on this path}}
    %s = idr.str.pack %v : !idr.box<@Chars> -> !idr.own<!idr.str>
    return %s : !idr.own<!idr.str>
  }
}

// -----

// A reference of its own to static data built only of atoms is exclusive:
// a pair of empty lists has no cell a take would hand out. One to static
// data holding a cell with fields is not: it shares that cell with every
// other copy, and a take of it would hand the cell out to build in.
module attributes {idr.stage = "owned"} {
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i64, !idr.box<@L>)
  }
  idr.data @P {
    idr.ctor @MkPair (!idr.box<@L>, !idr.box<@L>)
  }
  func.func private @empty() -> !idr.excl<!idr.data<@P>> {
    %c = idr.constant #idr.con<@P::@MkPair, [#idr.con<@L::@N, []>, #idr.con<@L::@N, []>]> : !idr.data<@P>
    %p = idr.dup %c : !idr.data<@P> -> !idr.excl<!idr.data<@P>>
    return %p : !idr.excl<!idr.data<@P>>
  }
  func.func private @one() -> !idr.excl<!idr.data<@P>> {
    // expected-note @+1 {{the value is defined here}}
    %c = idr.constant #idr.con<@P::@MkPair, [#idr.con<@L::@C, [1 : i64, #idr.con<@L::@N, []>]>, #idr.con<@L::@N, []>]> : !idr.data<@P>
    // expected-error @+1 {{takes an exclusive reference to a value that reaches cells other than atoms, which it shares}}
    %p = idr.dup %c : !idr.data<@P> -> !idr.excl<!idr.data<@P>>
    return %p : !idr.excl<!idr.data<@P>>
  }
}
