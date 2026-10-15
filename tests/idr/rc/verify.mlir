// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// The owned stage's rule: every reference is consumed exactly once on every
// path, and nothing is used once its last reference is gone. The grades say
// what each value holds: `!idr.own<T>` one reference of its own, plain T
// (a view) none. They also say which stage a program is in: one with an
// owned value is in the owned stage, so its verifier keeps the rule, and
// no attribute restates it.

// A value that holds references and is consumed once on every path, read
// through views where it is only read: accepted.
module {
  idr.func private @use(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length %v
    idr.drop %s : !idr.own<!idr.str>
    return %n : i64
  }
  idr.func private @twice(%s: !idr.own<!idr.str>) -> (!idr.own<!idr.str>, !idr.own<!idr.str>) {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %t = idr.dup %v : !idr.str
    return %s, %t : !idr.own<!idr.str>, !idr.own<!idr.str>
  }
  idr.func private @lend(%s: !idr.str) -> !idr.own<!idr.str> {
    %t = idr.str.append %s, %s : !idr.own<!idr.str>
    return %t : !idr.own<!idr.str>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

module {
  // expected-note @+1 {{the value is defined here}}
  idr.func private @twice(%s: !idr.own<!idr.str>) -> (!idr.own<!idr.str>, !idr.own<!idr.str>) {
    // expected-error @+1 {{consumes a reference that the value does not hold here}}
    return %s, %s : !idr.own<!idr.str>, !idr.own<!idr.str>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

module {
  // expected-note @+1 {{the value is defined here}}
  idr.func private @leak(%s: !idr.own<!idr.str>) -> i64 {
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length %v
    // expected-error @+1 {{returns while a value still holds a reference}}
    return %n : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

module {
  // expected-note @+1 {{the value is defined here}}
  idr.func private @late(%s: !idr.own<!idr.str>) -> i64 {
    idr.drop %s : !idr.own<!idr.str>
    // expected-error @+1 {{uses a value whose last reference is gone on this path}}
    %v = idr.borrow %s : !idr.own<!idr.str>
    %n = idr.str.length %v
    return %n : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A view holds no reference to give away: a consuming position (a field
// of a constructor) takes a reference of its own, never a view. (An owned
// value read directly is a type error already: the reading ops take plain
// values.)
!P = !idr.data<"P", plain [@P(!idr.str)]>
module {
  // expected-note @+1 {{the value is defined here}}
  idr.func private @give(%s: !idr.str) -> !idr.own<!P> {
    // expected-error @+1 {{consumes a view, which holds no reference}}
    %p = idr.con @P(%s) : (!idr.str) -> !idr.own<!P>
    return %p : !idr.own<!P>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// The regions of a match are alternatives, and must agree where they meet.
module {
  // expected-note @+1 {{the value is defined here}}
  idr.func private @branch(%b: i1, %s: !idr.own<!idr.str>) -> i64 {
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
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A field is a view that lives as long as the value it was read from,
// unless it takes a reference of its own.
!P = !idr.data<"P", plain [@P(!idr.str)]>
module {
  idr.func private @field(%p: !idr.own<!P>) -> !idr.own<!idr.str> {
    %v = idr.borrow %p : !idr.own<!P>
    %s = idr.field %v[@P, 0] : !P -> !idr.str
    %t = idr.dup %s : !idr.str
    idr.drop %p : !idr.own<!P>
    return %t : !idr.own<!idr.str>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

!P = !idr.data<"P", plain [@P(!idr.str)]>
module {
  idr.func private @field(%p: !idr.own<!P>) -> i64 {
    %v = idr.borrow %p : !idr.own<!P>
    // expected-note @+1 {{the value is defined here}}
    %s = idr.field %v[@P, 0] : !P -> !idr.str
    idr.drop %p : !idr.own<!P>
    // expected-error @+1 {{uses a value whose last reference is gone on this path}}
    %n = idr.str.length %s
    return %n : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A reuse builds in a cell of its own size.
!L = !idr.data<"L", plain [@N(), @C(i64, !idr.box<!idr.data<"L">>), @One(i64)]>
module {
  idr.func private @swap(%l: !idr.own<!idr.box<!L>>) -> !idr.own<!idr.box<!L>> {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.box<!L> -> (!idr.own<!idr.box<!L>>) {
    case @C(%h: i64, %t: !idr.box<!L>) {
      %w:3 = idr.take %l @C : !idr.own<!idr.box<!L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      // expected-error @+1 {{builds a cell of 16 bytes in the 24-byte cell of @C}}
      %o = idr.reuse %w#0 @One(%w#1) : (!idr.own<!idr.token>, i64) -> !idr.own<!idr.box<!L>>
      idr.drop %w#2 : !idr.own<!idr.box<!L>>
      idr.yield %o : !idr.own<!idr.box<!L>>
    }
    default {
      idr.yield %l : !idr.own<!idr.box<!L>>
    }
    }
    return %r : !idr.own<!idr.box<!L>>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A take consumes its value and gives each field a reference of its own,
// which is then consumed once like any other.
!L = !idr.data<"L", list [@N(), @C(i64, !idr.box<!idr.data<"L">>)]>
module {
  idr.func private @head(%l: !idr.own<!idr.box<!L>>) -> i64 {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.box<!L> -> (i64) {
    case @C(%h: i64, %t: !idr.box<!L>) {
      %w, %h2, %t2 = idr.take %l @C : !idr.own<!idr.box<!L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      idr.drop %w : !idr.own<!idr.token>
      idr.drop %t2 : !idr.own<!idr.box<!L>>
      idr.yield %h2 : i64
    }
    default {
      idr.drop %l : !idr.own<!idr.box<!L>>
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

!L = !idr.data<"L", list [@N(), @C(i64, !idr.box<!idr.data<"L">>)]>
module {
  idr.func private @head(%l: !idr.own<!idr.box<!L>>) -> i64 {
    %v = idr.borrow %l : !idr.own<!idr.box<!L>>
    %r = idr.match %v : !idr.box<!L> -> (i64) {
    case @C(%h: i64, %t: !idr.box<!L>) {
      // expected-note @+1 {{the value is defined here}}
      %w, %h2, %t2 = idr.take %l @C : !idr.own<!idr.box<!L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<!L>>)
      idr.drop %w : !idr.own<!idr.token>
      // expected-error @+1 {{ends a path on which a value still holds a reference}}
      idr.yield %h2 : i64
    }
    default {
      idr.drop %l : !idr.own<!idr.box<!L>>
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A string builder walks the cells of its list, a view, so it is refused
// once the reference the view borrows is gone, as a field read is.
!Chars = !idr.data<"Chars", list [@Nil(), @Cons(i32, !idr.box<!idr.data<"Chars">>)]>
module {
  idr.func private @pack(%l: !idr.own<!idr.box<!Chars>>) -> !idr.own<!idr.str> {
    // expected-note @+1 {{the value is defined here}}
    %v = idr.borrow %l : !idr.own<!idr.box<!Chars>>
    idr.drop %l : !idr.own<!idr.box<!Chars>>
    // expected-error @+1 {{uses a value whose last reference is gone on this path}}
    %s = idr.str.pack %v : !idr.box<!Chars> -> !idr.own<!idr.str>
    return %s : !idr.own<!idr.str>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}

// -----

// A reference of its own to static data built only of atoms is exclusive:
// a pair of empty lists has no cell a take would hand out. One to static
// data holding a cell with fields is not: it shares that cell with every
// other copy, and a take of it would hand the cell out to build in.
!L = !idr.data<"L", list [@N(), @C(i64, !idr.box<!idr.data<"L">>)]>
!P = !idr.data<"P", plain [@MkPair(!idr.box<!L>, !idr.box<!L>)]>
module {
  idr.func private @empty() -> !idr.excl<!P> {
    %c = idr.constant #idr.con<@MkPair, [#idr.con<@N, []>, #idr.con<@N, []>]> : !P
    %p = idr.dup %c : !P -> !idr.excl<!P>
    return %p : !idr.excl<!P>
  }
  idr.func private @one() -> !idr.excl<!P> {
    // expected-note @+1 {{the value is defined here}}
    %c = idr.constant #idr.con<@MkPair, [#idr.con<@C, [1 : i64, #idr.con<@N, []>]>, #idr.con<@N, []>]> : !P
    // expected-error @+1 {{takes an exclusive reference to a value that reaches cells other than atoms, which it shares}}
    %p = idr.dup %c : !P -> !idr.excl<!P>
    return %p : !idr.excl<!P>
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
