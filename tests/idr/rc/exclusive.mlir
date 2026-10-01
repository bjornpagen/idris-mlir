// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=tests-nothing=@bump -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// RUN: %status 1 idris-mlir-opt %s --idr-rc --idr-expect=holds=tests-nothing=@bump2 -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=SHARED < %t.err
// RUN: idris-mlir-opt %s --idr-rc '--idr-expect=holds=tests-nothing=@bump2$excl' -o /dev/null
// idr-rc proves which values hold the only reference to every cell they
// reach, and writes it into their types: a list built of fresh cells is
// exclusive, and so is what a function that only ever gets exclusive lists
// takes apart and rebuilds. Its takes test no count (tests-nothing). A
// list a caller uses again is shared, and the function it then goes to
// takes its cells apart with the runtime test; where the same function
// also gets fresh lists, those calls go to a copy specialized on the grade.
// CHECK-LABEL: func.func private @build(
// CHECK-SAME: -> !idr.excl<!idr.box<@L>>
// CHECK-LABEL: func.func private @bump(
// CHECK-SAME: %{{.*}}: !idr.excl<!idr.box<@L>>) -> !idr.excl<!idr.box<@L>>
// A nullary constructor is its atom: its take yields nothing.
// CHECK: idr.take %{{.*}} @L::@N : !idr.excl<!idr.box<@L>> -> ()
// CHECK: idr.take %{{.*}} @L::@C : !idr.excl<!idr.box<@L>> -> (!idr.excl<!idr.token>, i64, !idr.excl<!idr.box<@L>>)
// CHECK-LABEL: func.func private @bump2(
// CHECK-SAME: %{{.*}}: !idr.own<!idr.box<@L>>) -> !idr.excl<!idr.box<@L>>
// CHECK: idr.take %{{.*}} @L::@C : !idr.own<!idr.box<@L>> -> (!idr.own<!idr.token>, i64, !idr.own<!idr.box<@L>>)
// The calls of @bump2 with an exclusive list go to a copy of their own.
// CHECK-LABEL: func.func private @bump2$excl(
// CHECK-SAME: %{{.*}}: !idr.excl<!idr.box<@L>>) -> !idr.excl<!idr.box<@L>>
// CHECK: func.call @bump2$excl(
// CHECK-LABEL: func.func @root(
// CHECK: idr.share %{{.*}} : !idr.excl<!idr.box<@L>>
// CHECK: call @bump2$excl(
// SHARED: error: expected tests-nothing: idr.take in @bump2 tests a value of '!idr.own<!idr.box<@L>>', which is not exclusive
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i64, !idr.box<@L>)
  }
  func.func private @build(%n: i64) -> !idr.box<@L> {
    %r = idr.match_lit %n : i64 -> (!idr.box<@L>) {
    case 0 {
      %e = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
      idr.yield %e : !idr.box<@L>
    }
    default {
      %one = arith.constant 1 : i64
      %m = arith.subi %n, %one : i64
      %t = func.call @build(%m) : (i64) -> !idr.box<@L>
      %c = idr.con @L::@C(%n, %t) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  func.func private @bump(%l: !idr.box<@L>) -> !idr.box<@L> {
    %n = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %r = idr.match %l : !idr.box<@L> -> (!idr.box<@L>) {
    case @N() {
      idr.yield %n : !idr.box<@L>
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %one = arith.constant 1 : i64
      %h2 = arith.addi %h, %one : i64
      %t2 = func.call @bump(%t) : (!idr.box<@L>) -> !idr.box<@L>
      %c = idr.con @L::@C(%h2, %t2) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  func.func private @bump2(%l: !idr.box<@L>) -> !idr.box<@L> {
    %n = idr.constant #idr.con<@L::@N, []> : !idr.box<@L>
    %r = idr.match %l : !idr.box<@L> -> (!idr.box<@L>) {
    case @N() {
      idr.yield %n : !idr.box<@L>
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %one = arith.constant 1 : i64
      %h2 = arith.addi %h, %one : i64
      %t2 = func.call @bump2(%t) : (!idr.box<@L>) -> !idr.box<@L>
      %c = idr.con @L::@C(%h2, %t2) : (i64, !idr.box<@L>) -> !idr.box<@L>
      idr.yield %c : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  func.func private @sum(%l: !idr.box<@L>, %acc: i64) -> i64 {
    %r = idr.match %l : !idr.box<@L> -> (i64) {
    case @N() {
      idr.yield %acc : i64
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %a = arith.addi %acc, %h : i64
      %s = func.call @sum(%t, %a) : (!idr.box<@L>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func private @keep(%l: !idr.box<@L>) -> !idr.box<@L> {
    return %l : !idr.box<@L>
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %c3 = arith.constant 3 : i64
    %z = arith.constant 0 : i64
    // Fresh, read, then bumped: exclusive throughout.
    %a = func.call @build(%c3) : (i64) -> !idr.box<@L>
    %s1 = func.call @sum(%a, %z) : (!idr.box<@L>, i64) -> i64
    %b = func.call @bump(%a) : (!idr.box<@L>) -> !idr.box<@L>
    %s2 = func.call @sum(%b, %z) : (!idr.box<@L>, i64) -> i64
    // Kept by a callee and used again: shared from there on.
    %m = func.call @build(%c3) : (i64) -> !idr.box<@L>
    %k = func.call @keep(%m) : (!idr.box<@L>) -> !idr.box<@L>
    %p = func.call @bump2(%m) : (!idr.box<@L>) -> !idr.box<@L>
    %s3 = func.call @sum(%k, %z) : (!idr.box<@L>, i64) -> i64
    %s4 = func.call @sum(%p, %z) : (!idr.box<@L>, i64) -> i64
    // Fresh again, to the same function: exclusive, in a copy.
    %q = func.call @build(%c3) : (i64) -> !idr.box<@L>
    %r = func.call @bump2(%q) : (!idr.box<@L>) -> !idr.box<@L>
    %s5 = func.call @sum(%r, %z) : (!idr.box<@L>, i64) -> i64
    %w1 = idr.io.put_int signed %s1, %w : i64
    %w2 = idr.io.put_int signed %s2, %w1 : i64
    %w3 = idr.io.put_int signed %s3, %w2 : i64
    %w4 = idr.io.put_int signed %s4, %w3 : i64
    %w5 = idr.io.put_int signed %s5, %w4 : i64
    return %w5 : !idr.world
  }
}
