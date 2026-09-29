// RUN: idris-mlir-opt %s --idr-stack | FileCheck %s
// Stack space is bounded. A cell of more than 256 bytes stays on the heap
// (@large: 32 fields and the header, 264 bytes; @largest: 31 fields, 256
// bytes, is on the stack). A function's cells take at most 1024 bytes,
// in the order the function builds them (@frame: the fifth cell of 256
// bytes stays on the heap), and at most 64 bytes in a function on a cycle
// of calls, which may have many frames live at once (@recursive: the third
// cell of 24 bytes stays on the heap).

// CHECK-LABEL: func.func private @largest(
// CHECK: idr.con @Big::@Big(%{{[^)]*}}) {idr.stack} :
// CHECK-LABEL: func.func private @large(
// CHECK-NOT: idr.stack
// CHECK: return
// CHECK-LABEL: func.func private @frame(
// CHECK-COUNT-4: idr.con @Big::@Big(%{{[^)]*}}) {idr.stack} :
// CHECK-NEXT: idr.con @Big::@Big(%{{[^)]*}}) :
// CHECK-LABEL: func.func private @recursive(
// CHECK: idr.con @List::@Cons(%{{[^)]*}}) {idr.stack} :
// CHECK-NEXT: idr.con @List::@Cons(%{{[^)]*}}) {idr.stack} :
// CHECK-NEXT: idr.con @List::@Cons(%{{[^)]*}}) :
module attributes {idr.program} {
  idr.data @Big box {
    idr.ctor @Big tag 0 (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)
  }
  idr.data @Huge box {
    idr.ctor @Huge tag 0 (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)
  }
  idr.data @List box {
    idr.ctor @Nil tag 0 ()
    idr.ctor @Cons tag 1 (i64, !idr.box<@List>)
  }
  func.func private @firstBig(%b: !idr.box<@Big>) -> i64 {
    %x = idr.field %b[@Big, 0] : !idr.box<@Big> -> i64
    return %x : i64
  }
  func.func private @firstHuge(%b: !idr.box<@Huge>) -> i64 {
    %x = idr.field %b[@Huge, 0] : !idr.box<@Huge> -> i64
    return %x : i64
  }
  func.func private @largest(%a: i64) -> i64 {
    %b = idr.con @Big::@Big(%a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a) : (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64) -> !idr.box<@Big>
    %x = func.call @firstBig(%b) : (!idr.box<@Big>) -> i64
    return %x : i64
  }
  func.func private @large(%a: i64) -> i64 {
    %b = idr.con @Huge::@Huge(%a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a) : (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64) -> !idr.box<@Huge>
    %x = func.call @firstHuge(%b) : (!idr.box<@Huge>) -> i64
    return %x : i64
  }
  func.func private @frame(%a: i64) -> i64 {
    %b0 = idr.con @Big::@Big(%a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a) : (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64) -> !idr.box<@Big>
    %b1 = idr.con @Big::@Big(%a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a) : (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64) -> !idr.box<@Big>
    %b2 = idr.con @Big::@Big(%a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a) : (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64) -> !idr.box<@Big>
    %b3 = idr.con @Big::@Big(%a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a) : (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64) -> !idr.box<@Big>
    %b4 = idr.con @Big::@Big(%a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a, %a) : (i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64) -> !idr.box<@Big>
    %x0 = func.call @firstBig(%b0) : (!idr.box<@Big>) -> i64
    %x1 = func.call @firstBig(%b1) : (!idr.box<@Big>) -> i64
    %x2 = func.call @firstBig(%b2) : (!idr.box<@Big>) -> i64
    %x3 = func.call @firstBig(%b3) : (!idr.box<@Big>) -> i64
    %x4 = func.call @firstBig(%b4) : (!idr.box<@Big>) -> i64
    %s1 = arith.addi %x0, %x1 : i64
    %s2 = arith.addi %s1, %x2 : i64
    %s3 = arith.addi %s2, %x3 : i64
    %s4 = arith.addi %s3, %x4 : i64
    return %s4 : i64
  }
  // recursive n = if n == 0 then 0 else head [n] + head [n] + head [n] + recursive (n - 1)
  func.func private @recursive(%a: i64, %t: !idr.box<@List>) -> i64 {
    %c0 = idr.con @List::@Cons(%a, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %c1 = idr.con @List::@Cons(%a, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %c2 = idr.con @List::@Cons(%a, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %r = idr.match_lit %a : i64 -> (i64) {
    case 0 {
      idr.yield %a : i64
    }
    default {
      %x0 = func.call @head(%c0) : (!idr.box<@List>) -> i64
      %x1 = func.call @head(%c1) : (!idr.box<@List>) -> i64
      %x2 = func.call @head(%c2) : (!idr.box<@List>) -> i64
      %one = arith.constant 1 : i64
      %m = arith.subi %a, %one : i64
      %rest = func.call @recursive(%m, %t) : (i64, !idr.box<@List>) -> i64
      %s1 = arith.addi %x0, %x1 : i64
      %s2 = arith.addi %s1, %x2 : i64
      %s3 = arith.addi %s2, %rest : i64
      idr.yield %s3 : i64
    }
    }
    return %r : i64
  }
  func.func private @head(%l: !idr.box<@List>) -> i64 {
    %r = idr.match %l : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<@List>) {
      idr.yield %h : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  func.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
