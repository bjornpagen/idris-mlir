// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=tests-nothing=@sumAfterTag -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc | FileCheck %s
// RUN: idris-mlir-opt %s --idr-rc --idr-lower | FileCheck %s --check-prefix=LOWER
// A box that dies in the region of the match that saw its constructor is
// taken apart where it dies even when no constructor is built in its cell
// (Perceus's drop specialization): one test of its count, instead of a
// reference taken for each field the region keeps and a drop of the box
// that walks its children to give theirs back. `sumAfterTag` reads the
// list's tag and then sums its tail: the tail moves out of the take with
// no reference of its own (no idr.dup), and the cell is freed. A field
// nothing wants dies with the box: where the box held the only reference
// the field's is dropped at the take, and where it was shared nothing
// happens to the field, instead of a reference taken for it and given up
// again. `tail` drops the head of a list of lists: on the shared path only
// the tail is counted, and no count is touched after the test. A box no
// field of which that holds references lives on past it gains nothing from
// the test (Perceus specializes a drop only where the children are used),
// and is dropped where it dies: `headOnly` reads a list's head, a number,
// and its tail dies with it; `numbers` reads a cell of two numbers.
// CHECK-LABEL: func.func private @sumAfterTag(
// CHECK-NOT: idr.dup
// CHECK: idr.take
// CHECK-NOT: idr.dup
// CHECK: return
// CHECK-LABEL: func.func private @headOnly(
// CHECK-NOT: idr.take %{{.*}} @L::@C
// CHECK: idr.drop
// CHECK-NOT: idr.take %{{.*}} @L::@C
// CHECK: return
// CHECK-LABEL: func.func private @numbers(
// CHECK-NOT: idr.take %{{.*}} @V::@V1
// CHECK: idr.drop
// CHECK-NOT: idr.take %{{.*}} @V::@V1
// CHECK: return
// LOWER-LABEL: func.func private @tail(
// LOWER: scf.if
// LOWER-NEXT: llvm.call @idris_rt_dec(
// LOWER-NEXT: scf.yield
// LOWER-NEXT: } else {
// LOWER-COUNT-1: llvm.call @idris_rt_inc(
// LOWER-NOT: llvm.call @idris_rt_inc(
// LOWER: llvm.call @idris_rt_dec(
// LOWER: }
// LOWER-NOT: llvm.call @idris_rt_dec(
// LOWER: llvm.call @idris_rt_free_cell(
// LOWER-NOT: llvm.call @idris_rt_dec(
// LOWER: return
// LOWER-LABEL: func.func private @tailX(
// LOWER-NOT: scf.if
// LOWER-NOT: idris_rt_inc
// LOWER: llvm.call @idris_rt_dec(
// LOWER-NOT: idris_rt_dec
// LOWER: llvm.call @idris_rt_free_cell(
// LOWER-NOT: idris_rt_dec
// LOWER: return
module attributes {idr.program} {
  idr.data @L box {
    idr.ctor @N ()
    idr.ctor @C (i64, !idr.box<@L>)
  }
  idr.data @LL box {
    idr.ctor @NN ()
    idr.ctor @CC (!idr.box<@L>, !idr.box<@LL>)
  }
  idr.data @V box {
    idr.ctor @V0 ()
    idr.ctor @V1 (i64, i64)
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
  // The list is given back empty, and otherwise read (its tag) before its
  // tail is summed and a list of that length built: it dies after the read.
  func.func private @sumAfterTag(%l: !idr.box<@L>) -> !idr.box<@L> {
    %r = idr.match %l : !idr.box<@L> -> (!idr.box<@L>) {
    case @N() {
      idr.yield %l : !idr.box<@L>
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %k = idr.tag %l : !idr.box<@L>
      %s = func.call @sum(%t, %k) : (!idr.box<@L>, i64) -> i64
      %b = func.call @build(%s) : (i64) -> !idr.box<@L>
      idr.yield %b : !idr.box<@L>
    }
    }
    return %r : !idr.box<@L>
  }
  // The head, a list, is nothing the result holds.
  func.func private @tail(%l: !idr.box<@LL>) -> !idr.box<@LL> {
    %r = idr.match %l : !idr.box<@LL> -> (!idr.box<@LL>) {
    case @NN() {
      idr.yield %l : !idr.box<@LL>
    }
    case @CC(%h: !idr.box<@L>, %t: !idr.box<@LL>) {
      idr.yield %t : !idr.box<@LL>
    }
    }
    return %r : !idr.box<@LL>
  }
  // The same, on a list its caller never shares.
  func.func private @tailX(%l: !idr.box<@LL>) -> !idr.box<@LL> {
    %r = idr.match %l : !idr.box<@LL> -> (!idr.box<@LL>) {
    case @NN() {
      idr.yield %l : !idr.box<@LL>
    }
    case @CC(%h: !idr.box<@L>, %t: !idr.box<@LL>) {
      idr.yield %t : !idr.box<@LL>
    }
    }
    return %r : !idr.box<@LL>
  }
  // A list of n, read (its tag), and then only its head, a number, used.
  func.func private @headOnly(%n: i64) -> i64 {
    %l = func.call @build(%n) : (i64) -> !idr.box<@L>
    %r = idr.match %l : !idr.box<@L> -> (i64) {
    case @N() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @C(%h: i64, %t: !idr.box<@L>) {
      %k = idr.tag %l : !idr.box<@L>
      %s = arith.addi %h, %k : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func private @mkV(%n: i64) -> !idr.box<@V> {
    %v = idr.con @V::@V1(%n, %n) : (i64, i64) -> !idr.box<@V>
    return %v : !idr.box<@V>
  }
  // A cell of two numbers, read (its tag), and then its numbers used.
  func.func private @numbers(%n: i64) -> i64 {
    %v = func.call @mkV(%n) : (i64) -> !idr.box<@V>
    %r = idr.match %v : !idr.box<@V> -> (i64) {
    case @V0() {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    case @V1(%a: i64, %b: i64) {
      %k = idr.tag %v : !idr.box<@V>
      %s = arith.addi %a, %b : i64
      %t = arith.addi %s, %k : i64
      idr.yield %t : i64
    }
    }
    return %r : i64
  }
  func.func @root(%w: !idr.world) -> !idr.world {
    %three = arith.constant 3 : i64
    %two = arith.constant 2 : i64
    %nn = idr.constant #idr.con<@LL::@NN, []> : !idr.box<@LL>
    %a = func.call @build(%three) : (i64) -> !idr.box<@L>
    %r = func.call @sumAfterTag(%a) : (!idr.box<@L>) -> !idr.box<@L>
    // Kept by its caller across the call: shared.
    %x = func.call @build(%three) : (i64) -> !idr.box<@L>
    %ll = idr.con @LL::@CC(%x, %nn) : (!idr.box<@L>, !idr.box<@LL>) -> !idr.box<@LL>
    %t1 = func.call @tail(%ll) : (!idr.box<@LL>) -> !idr.box<@LL>
    %c = idr.tag %ll : !idr.box<@LL>
    // Fresh, and never used again: exclusive.
    %y = func.call @build(%two) : (i64) -> !idr.box<@L>
    %ll2 = idr.con @LL::@CC(%y, %nn) : (!idr.box<@L>, !idr.box<@LL>) -> !idr.box<@LL>
    %t2 = func.call @tailX(%ll2) : (!idr.box<@LL>) -> !idr.box<@LL>
    %d = idr.tag %r : !idr.box<@L>
    %e = idr.tag %t1 : !idr.box<@LL>
    %f = idr.tag %t2 : !idr.box<@LL>
    %cd = arith.addi %c, %d : i64
    %ef = arith.addi %e, %f : i64
    %s = arith.addi %cd, %ef : i64
    %ho = func.call @headOnly(%three) : (i64) -> i64
    %nu = func.call @numbers(%two) : (i64) -> i64
    %hn = arith.addi %ho, %nu : i64
    %all = arith.addi %s, %hn : i64
    %w2 = idr.io.put_int signed %all, %w : i64
    return %w2 : !idr.world
  }
}
