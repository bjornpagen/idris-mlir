// RUN: idris-mlir-opt %s --idr-stack --idr-tail-loops | FileCheck %s
// A cell passed to a parameter that its callee only reads is live only while
// the call runs, inside the caller's frame: marked. That holds through
// recursion (@sum passes the tail to itself), mutual recursion (@evens and
// @odds) and a loop that only reads it (@sumAcc, whose self tail call
// idr-tail-loops makes a loop). A parameter escapes when its callee returns
// it (@same), stores it (@push), or passes it to a parameter that escapes
// (@viaSame); so does every argument of a function without a body.

// CHECK-LABEL: func.func private @callers(
// CHECK: %[[SUM:.*]] = idr.con @List::@Cons(%{{[^)]*}}) {idr.stack} :
// CHECK: %[[EVENS:.*]] = idr.con @List::@Cons(%{{[^)]*}}) {idr.stack} :
// CHECK: %[[LOOP:.*]] = idr.con @List::@Cons(%{{[^)]*}}) {idr.stack} :
// CHECK: %[[SAME:.*]] = idr.con @List::@Cons(%{{[^)]*}}) :
// CHECK: %[[VIA:.*]] = idr.con @List::@Cons(%{{[^)]*}}) :
// CHECK: %[[PUSH:.*]] = idr.con @List::@Cons(%{{[^)]*}}) :
// CHECK: %[[EXTERNAL:.*]] = idr.con @List::@Cons(%{{[^)]*}}) :
// CHECK: call @sum(%[[SUM]])
// CHECK: call @evens(%[[EVENS]])
// CHECK: call @sumAcc(%{{.*}}, %[[LOOP]])
// CHECK: call @same(%[[SAME]])
// CHECK: call @viaSame(%[[VIA]])
// CHECK: call @push(%[[PUSH]])
// CHECK: call @external(%[[EXTERNAL]])
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  func.func private @sum(%l: !idr.box<@List>) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      %s = func.call @sum(%t) : (!idr.box<@List>) -> i64
      %a = arith.addi %h, %s : i64
      idr.yield %a : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  func.func private @evens(%l: !idr.box<@List>) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      %s = func.call @odds(%t) : (!idr.box<@List>) -> i64
      %a = arith.addi %h, %s : i64
      idr.yield %a : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  func.func private @odds(%l: !idr.box<@List>) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      %s = func.call @evens(%t) : (!idr.box<@List>) -> i64
      idr.yield %s : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  func.func private @sumAcc(%acc: i64, %l: !idr.box<@List>) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      %a = arith.addi %acc, %h : i64
      %s = func.call @sumAcc(%a, %t) : (i64, !idr.box<@List>) -> i64
      idr.yield %s : i64
    }
    default {
      idr.yield %acc : i64
    }
    }
    return %r : i64
  }
  func.func private @same(%l: !idr.box<@List>) -> !idr.box<@List> {
    return %l : !idr.box<@List>
  }
  func.func private @viaSame(%l: !idr.box<@List>) -> i64 {
    %m = func.call @same(%l) : (!idr.box<@List>) -> !idr.box<@List>
    %s = func.call @sum(%m) : (!idr.box<@List>) -> i64
    return %s : i64
  }
  func.func private @push(%l: !idr.box<@List>) -> !idr.box<@List> {
    %zero = arith.constant 0 : i64
    %c = idr.con @List::@Cons(%zero, %l) : (i64, !idr.box<@List>) -> !idr.box<@List>
    return %c : !idr.box<@List>
  }
  func.func private @external(!idr.box<@List>) -> i64
  func.func private @callers(%x: i64, %t: !idr.box<@List>) -> i64 {
    %a = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %b = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %c = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %d = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %e = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %f = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %g = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %ra = func.call @sum(%a) : (!idr.box<@List>) -> i64
    %rb = func.call @evens(%b) : (!idr.box<@List>) -> i64
    %rc = func.call @sumAcc(%x, %c) : (i64, !idr.box<@List>) -> i64
    %md = func.call @same(%d) : (!idr.box<@List>) -> !idr.box<@List>
    %rd = func.call @sum(%md) : (!idr.box<@List>) -> i64
    %re = func.call @viaSame(%e) : (!idr.box<@List>) -> i64
    %mf = func.call @push(%f) : (!idr.box<@List>) -> !idr.box<@List>
    %rf = func.call @sum(%mf) : (!idr.box<@List>) -> i64
    %rg = func.call @external(%g) : (!idr.box<@List>) -> i64
    %s1 = arith.addi %ra, %rb : i64
    %s2 = arith.addi %s1, %rc : i64
    %s3 = arith.addi %s2, %rd : i64
    %s4 = arith.addi %s3, %re : i64
    %s5 = arith.addi %s4, %rf : i64
    %s6 = arith.addi %s5, %rg : i64
    return %s6 : i64
  }
  func.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
