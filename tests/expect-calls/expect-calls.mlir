// RUN: idris-mlir-opt %s --idr-expect=holds=one-clone=@inc,not-called=@absent,specialized-once=@count,calls=@main:@inc -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=one-clone=@twice,not-called=@gone,specialized-once=@walk,contified,calls=@main:@absent -verify-diagnostics -o /dev/null
// What the calls of a program say, by upstream's call interface, so a
// module of any dialect states them alike. A copy is a function whose
// location names what it was made from. @inc is called twice, both times
// of itself; @twice and its copy are both called, so its calls reach two
// functions. The copy of @count calls only itself; a copy of @walk calls
// another copy. @step is called once, from @loop, and calls @loop back: a
// continuation still a function. @gone is still called, and nothing calls
// @absent, which the module never had.
// expected-error @below {{expected one-clone: }}
module {
  func.func private @inc(%x: i64) -> i64 {
    %one = arith.constant 1 : i64
    %y = arith.addi %x, %one : i64
    return %y : i64
  }
  func.func private @twice(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  func.func private @twice_1(%x: i64) -> i64 {
    %y = arith.addi %x, %x : i64
    return %y : i64
  } loc("twice")
  func.func private @count(%n: i64) -> i64 {
    %r = func.call @count(%n) : (i64) -> i64
    return %r : i64
  }
  func.func private @count_1(%n: i64) -> i64 {
    %r = func.call @count_1(%n) : (i64) -> i64
    return %r : i64
  } loc("count")
  func.func private @walk(%n: i64) -> i64 {
    %r = func.call @walk(%n) : (i64) -> i64
    return %r : i64
  }
  func.func private @walk_1(%n: i64) -> i64 {
    // expected-error @below {{expected specialized-once: }}
    %r = func.call @walk_2(%n) : (i64) -> i64
    return %r : i64
  } loc("walk")
  func.func private @walk_2(%n: i64) -> i64 {
    %r = func.call @walk_2(%n) : (i64) -> i64
    return %r : i64
  } loc("walk")
  func.func private @loop(%n: i64) -> i64 {
    // expected-error @below {{expected contified: }}
    %r = func.call @step(%n) : (i64) -> i64
    return %r : i64
  }
  func.func private @step(%n: i64) -> i64 {
    %r = func.call @loop(%n) : (i64) -> i64
    return %r : i64
  }
  func.func private @gone(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error @below {{expected calls: }}
  func.func @main(%a: i64) -> i64 {
    %b = func.call @inc(%a) : (i64) -> i64
    %c = func.call @inc(%b) : (i64) -> i64
    %d = func.call @twice(%c) : (i64) -> i64
    %e = func.call @twice_1(%d) : (i64) -> i64
    %f = func.call @count_1(%e) : (i64) -> i64
    %g = func.call @walk_1(%f) : (i64) -> i64
    %h = func.call @loop(%g) : (i64) -> i64
    // expected-error @below {{expected not-called: }}
    %i = func.call @gone(%h) : (i64) -> i64
    return %i : i64
  }
}
