// RUN: idris-mlir-opt %s -split-input-file -verify-diagnostics
// A value of !idr.lin<T> is used at most once on every path: by
// idr.lin.use, or by a position whose type is linear too. Any value enters
// a linear position through idr.lin.enter. The world is linear by its own
// type, and world-once holds its refusals; once in each region
// of a match is once on each path for it too (the last split). The rule is
// one function's, checked by idr.func's own verifier after the ops of its
// body, so it holds in a module that is no whole program as in one that
// is, and a second use is refused at the op of the value's own block after
// which it has been used twice: the use itself, or the match whose region
// holds it. So on one path, also when the first use is before a match and
// the second in one of its regions, or both are in nested regions of one
// path, the match is refused; and one region may leave it unused.

!Box = !idr.data<"Box">
#types = #idr.types<
  "Box" = plain [@MkBox(!idr.lin<i64>)]
>
idr.program @"linear-twice" root(@root) stage(first) types #types {
idr.func @take(%x: !idr.lin<i64>) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  return %v : i64
}
// At most once on each path: one region may leave it unused.
idr.func @one_side(%b: i64, %x: !idr.lin<i64>) -> i64 {
  %r = idr.match_lit %b : i64 -> (i64) {
  case 0 {
    %v = idr.lin.use %x : !idr.lin<i64>
    idr.yield %v : i64
  }
  default(%d: i64) {
    idr.yield %b : i64
  }
  }
  return %r : i64
}
// Once on each path: passed on in one region, used in the other.
idr.func @branch(%b: i64, %x: !idr.lin<i64>) -> i64 {
  %r = idr.match_lit %b : i64 -> (i64) {
  case 0 {
    %t = idr.call @take(%x) : (!idr.lin<i64>) -> i64
    idr.yield %t : i64
  }
  default(%d: i64) {
    %v = idr.lin.use %x : !idr.lin<i64>
    idr.yield %v : i64
  }
  }
  return %r : i64
}
// A field of a linear type holds the value itself.
idr.func @boxed(%x: i64) -> !Box {
  %e = idr.lin.enter %x : !idr.lin<i64>
  %c = idr.con !Box @MkBox(%e : !idr.lin<i64>)
  return %c : !Box
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @"linear-twice" root(@root) stage(first) types #idr.types<> {
  idr.func @twice(%x: !idr.lin<i64>) -> i64 {
    %a = idr.lin.use %x : !idr.lin<i64>
    // expected-error @+1 {{already used on the same path}}
    %b = idr.lin.use %x : !idr.lin<i64>
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// Entered once, a value is linear from then on.
idr.program @"linear-twice" root(@root) stage(first) types #idr.types<> {
idr.func @take(%x: !idr.lin<i64>) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  return %v : i64
}
idr.func @f(%x: i64) -> i64 {
  %e = idr.lin.enter %x : !idr.lin<i64>
  %a = idr.call @take(%e) : (!idr.lin<i64>) -> i64
  // expected-error @+1 {{already used on the same path}}
  %b = idr.call @take(%e) : (!idr.lin<i64>) -> i64
  %s = arith.addi %a, %b : i64
  return %s : i64
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @"linear-twice" root(@root) stage(first) types #idr.types<> {
  // expected-error @+1 {{expects no grade of '!idr.world', which is used exactly once by its type}}
  idr.func @f(%w: !idr.lin<!idr.world>) {
    return
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A match takes a linear value apart, as its one use, and binds each
// field at the product of the value's quantity and the field's: of a
// linear value, as the constructor holds the field; of a value used many
// times, as used many times. A default region gets a linear value it did
// not take apart back.
!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@MkP(i64, !idr.lin<i64>), @Empty()]
>
idr.program @"linear-twice" root(@root) stage(first) types #types {
idr.func @snd(%p: !idr.lin<!P>) -> i64 {
  %r = idr.match %p : !idr.lin<!P> -> (i64) {
  case @MkP(%a: i64, %b: !idr.lin<i64>) {
    %x = idr.lin.use %b : !idr.lin<i64>
    idr.yield %x : i64
  }
  default(%q: !idr.lin<!P>) {
    %s = idr.call @snd(%q) : (!idr.lin<!P>) -> i64
    idr.yield %s : i64
  }
  }
  return %r : i64
}
idr.func @shared(%p: !P) -> i64 {
  %r = idr.match %p : !P -> (i64) {
  case @MkP(%a: i64, %b: i64) {
    %x = arith.addi %b, %b : i64
    idr.yield %x : i64
  }
  default(%d: !P) {
    %z = arith.constant 0 : i64
    idr.yield %z : i64
  }
  }
  return %r : i64
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@MkP(!idr.lin<i64>)]
>
idr.program @"linear-twice" root(@root) stage(first) types #types {
  idr.func @f(%p: !P) -> i64 {
    // expected-error @+1 {{case @MkP must take the constructor's fields at the scrutinee's grade, 'i64'}}
    %r = idr.match %p : !P -> (i64) {
    case @MkP(%a: !idr.lin<i64>) {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
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

!P = !idr.data<"P">
#types = #idr.types<
  "P" = plain [@MkP(i64)]
>
idr.program @"linear-twice" root(@root) stage(first) types #types {
  idr.func @f(%p: !idr.lin<!P>) -> i64 {
    // expected-error @+1 {{expects a default region}}
    %r = idr.match %p : !idr.lin<!P> -> (i64) {
    case @MkP(%a: i64) {
      idr.yield %a : i64
    }
    default(%q: !P) {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
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

// A closure holding a linear value is linear too, by its type: it is at
// quantity one exactly when a capture is, and is used once, applied or
// passed on, as any linear value.
idr.program @"linear-twice" root(@root) stage(higher) types #idr.types<> {
idr.func @add(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  %s = arith.addi %v, %y : i64
  return %s : i64
}
idr.func @now(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.lin<!idr.fn<(i64) -> (i64)>>
  %r = idr.apply %f(%y) : !idr.lin<!idr.fn<(i64) -> (i64)>>
  return %r : i64
}
idr.func @later(%x: !idr.lin<i64>) -> !idr.lin<!idr.fn<(i64) -> (i64)>> {
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.lin<!idr.fn<(i64) -> (i64)>>
  return %f : !idr.lin<!idr.fn<(i64) -> (i64)>>
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @"linear-twice" root(@root) stage(higher) types #idr.types<> {
idr.func @add(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  %s = arith.addi %v, %y : i64
  return %s : i64
}
idr.func @twice(%x: !idr.lin<i64>, %y: i64) -> i64 {
  // expected-error @+1 {{failed to verify that its result is at quantity one exactly when a capture is}}
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.fn<(i64) -> (i64)>
  %a = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
  %b = idr.apply %f(%y) : !idr.fn<(i64) -> (i64)>
  %s = arith.addi %a, %b : i64
  return %s : i64
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

idr.program @"linear-twice" root(@root) stage(higher) types #idr.types<> {
idr.func @add(%x: !idr.lin<i64>, %y: i64) -> i64 {
  %v = idr.lin.use %x : !idr.lin<i64>
  %s = arith.addi %v, %y : i64
  return %s : i64
}
idr.func @keep(%f: !idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)> {
  return %f : !idr.fn<(i64) -> (i64)>
}
idr.func @passed(%x: !idr.lin<i64>) -> !idr.fn<(i64) -> (i64)> {
  // expected-error @+1 {{failed to verify that its result is at quantity one exactly when a capture is}}
  %f = idr.closure @add(%x) : (!idr.lin<i64>) -> !idr.fn<(i64) -> (i64)>
  %k = idr.call @keep(%f) : (!idr.fn<(i64) -> (i64)>) -> !idr.fn<(i64) -> (i64)>
  return %k : !idr.fn<(i64) -> (i64)>
}
idr.func @root() -> i64 {
  %z = arith.constant 0 : i64
  return %z : i64
}
}

// -----

// Once in each region of a match is once on each path.
idr.program @"linear-twice" root(@root) stage(first) types #idr.types<> {
  idr.func @branch(%b: i64, %w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    %r = idr.match_lit %b : i64 -> (!idr.world) {
    case 0 {
      %w1 = idr.io.put_char %c, %w
      idr.yield %w1 : !idr.world
    }
    default(%d: i64) {
      idr.yield %w : !idr.world
    }
    }
    return %r : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}

// -----

// A use before a match and one in a region of it are on one path.
idr.program @"linear-twice" root(@root) stage(first) types #idr.types<> {
  idr.func @before(%b: i64, %x: !idr.lin<i64>) -> i64 {
    %a = idr.lin.use %x : !idr.lin<i64>
    // expected-error @+1 {{already used on the same path}}
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      %v = idr.lin.use %x : !idr.lin<i64>
      idr.yield %v : i64
    }
    default(%d: i64) {
      idr.yield %a : i64
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

// So are uses in a region and in a region nested in it.
idr.program @"linear-twice" root(@root) stage(first) types #idr.types<> {
  idr.func @nested(%b: i64, %c: i64, %x: !idr.lin<i64>) -> i64 {
    // expected-error @+1 {{already used on the same path}}
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      %a = idr.lin.use %x : !idr.lin<i64>
      %s = idr.match_lit %c : i64 -> (i64) {
      case 0 {
        %v = idr.lin.use %x : !idr.lin<i64>
        idr.yield %v : i64
      }
      default(%e: i64) {
        idr.yield %a : i64
      }
      }
      idr.yield %s : i64
    }
    default(%d: i64) {
      idr.yield %b : i64
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
