// RUN: idris-mlir-opt %s --idr-effects --test-idr-facts -verify-diagnostics=only-expected -o /dev/null
// RUN: idris-mlir-opt %s --idr-effects --cse --canonicalize '--idr-expect=holds=never-calls=@main:@square,call-order=@main:[@partial,@partial,@divides,@divides,@anything,@proved_calls_partial,@writes]' -o /dev/null
// What an op answers about itself, from its own effects as MLIR reads
// them. An unused op is dead when it does no more than read or allocate
// its results, and two equal ops are one value when it has no effect at
// all, as upstream's dead code removal and CSE read its effects; an op may
// be moved across anything when it only computes, as a division does once
// its guard has run, and delayed when it performs no IO, though it may
// crash, as a guard may, or not return. A call answers from the effects it
// holds, which idr-effects writes with its callee's, so a call of a
// function that only computes is dead when nothing reads it. A match
// answers from its regions, where an arm that crashes does what the crash
// does. By the time effects are known, no closure is passed to a call.
// Upstream's dead code removal and CSE read these answers alone: the calls
// of @square go, and every call that may crash, not return or perform IO
// is kept, each one, two equal ones included.

idr.program @queries root(@root) stage(first) {
  idr.func @square(%x: i64) -> i64 attributes {total} {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @partial(%x: i64) -> i64 {
    %r = arith.muli %x, %x : i64
    return %r : i64
  }
  idr.func @divides(%x: i64) -> i64 attributes {total} {
    %y = idr.check.nonzero %x, "division by zero" : i64
    %r = idr.divs %x, %y : i64
    return %r : i64
  }
  idr.func @writes(%x: i64, %w: !idr.world) -> !idr.world attributes {total} {
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    return %w1 : !idr.world
  }
  // May do anything: it performs IO, and Idris did not prove that it ends.
  idr.func @anything(%x: i64) -> i64 {
    %w = idr.world.new
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    %r = idr.call @anything(%x) : (i64) -> i64
    return %r : i64
  }
  // A function Idris proved that reaches one it did not, as a call of an
  // interface's method reaches its implementation, may not return either.
  idr.func @proved_calls_partial(%x: i64) -> i64 attributes {total} {
    %r = idr.call @partial(%x) : (i64) -> i64
    return %r : i64
  }

  idr.func @main(%x: i64, %y: i64, %w: !idr.world) -> !idr.world {
    %three = arith.constant 3 : i64
    // expected-remark @below {{facts: [drop move delay merge]}}
    %a = idr.call @square(%x) : (i64) -> i64
    // expected-remark @below {{facts: [drop move delay merge]}}
    %b = idr.call @square(%three) : (i64) -> i64
    // expected-remark @below {{facts: [delay]}}
    %c = idr.call @partial(%x) : (i64) -> i64
    // expected-remark @below {{facts: [delay]}}
    %d = idr.call @partial(%three) : (i64) -> i64
    // expected-remark @below {{facts: [delay]}}
    %e = idr.call @divides(%x) : (i64) -> i64
    // expected-remark @below {{facts: [delay]}}
    %e2 = idr.call @divides(%x) : (i64) -> i64
    // expected-remark @below {{facts: []}}
    %f = idr.call @anything(%three) : (i64) -> i64
    // expected-remark @below {{facts: [delay]}}
    %pp = idr.call @proved_calls_partial(%x) : (i64) -> i64
    // expected-remark @below {{facts: []}}
    %w1 = idr.call @writes(%x, %w) : (i64, !idr.world) -> !idr.world
    // expected-remark @below {{facts: [delay]}}
    %y1 = idr.check.nonzero %y, "division by zero" : i64
    // expected-remark @below {{facts: [drop move delay merge]}}
    %q = idr.divs %x, %y1 : i64
    // expected-remark @below {{facts: [drop move delay merge]}}
    %r = idr.divs %x, %three : i64
    // expected-remark @below {{facts: [delay]}}
    %n = idr.match_lit %x : i64 -> (i64) {
    case 0 {
      idr.yield %y : i64
    }
    default(%d1: i64) {
      idr.crash "no"
      ub.unreachable
    }
    }
    %ch = arith.constant 65 : i32
    // expected-remark @below {{facts: []}}
    %w2 = idr.io.put_char %ch, %w1
    return %w2 : !idr.world
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
