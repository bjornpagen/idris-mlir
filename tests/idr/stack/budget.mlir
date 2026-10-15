// RUN: idris-mlir-opt %s --idr-stack | FileCheck %s
// Stack space is bounded. A cell of more than 256 bytes stays on the heap
// (@large: 32 fields and the header, 264 bytes; @largest: 31 fields, 256
// bytes, is on the stack). A function's cells take at most 1024 bytes,
// in the order the function builds them (@frame: the fifth cell of 256
// bytes stays on the heap), and at most 64 bytes in a function on a cycle
// of calls, which may have many frames live at once (@recursive: the third
// cell of 24 bytes stays on the heap).

// CHECK-LABEL: idr.func @largest(
// CHECK: con {{.*}}@Big({{[^)]*}}) stack
// CHECK-LABEL: idr.func @large(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func @frame(
// CHECK-COUNT-4: con {{.*}}@Big({{[^)]*}}) stack
// CHECK-NEXT: con {{.*}}@Big({{[^)]*}}){{$}}
// CHECK-LABEL: idr.func @recursive(
// CHECK: con {{.*}}@Cons({{[^)]*}}) stack
// CHECK-NEXT: con {{.*}}@Cons({{[^)]*}}) stack
// CHECK-NEXT: con {{.*}}@Cons({{[^)]*}}){{$}}
!Big = !idr.data<"Big", plain [@Big(i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)]>
!Huge = !idr.data<"Huge", plain [@Huge(i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64, i64)]>
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @budget root(@Prog.main) stage(first) {
  idr.func @firstBig(%b: !idr.box<!Big>) -> i64 {
    %x = idr.field %b : !idr.box<!Big> @Big[0] -> i64
    return %x : i64
  }
  idr.func @firstHuge(%b: !idr.box<!Huge>) -> i64 {
    %x = idr.field %b : !idr.box<!Huge> @Huge[0] -> i64
    return %x : i64
  }
  idr.func @largest(%a: i64) -> i64 {
    %b = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %x = idr.call @firstBig(%b) : (!idr.box<!Big>) -> i64
    return %x : i64
  }
  idr.func @large(%a: i64) -> i64 {
    %b = idr.con !idr.box<!Huge> @Huge(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %x = idr.call @firstHuge(%b) : (!idr.box<!Huge>) -> i64
    return %x : i64
  }
  idr.func @frame(%a: i64) -> i64 {
    %b0 = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %b1 = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %b2 = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %b3 = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %b4 = idr.con !idr.box<!Big> @Big(%a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64, %a : i64)
    %x0 = idr.call @firstBig(%b0) : (!idr.box<!Big>) -> i64
    %x1 = idr.call @firstBig(%b1) : (!idr.box<!Big>) -> i64
    %x2 = idr.call @firstBig(%b2) : (!idr.box<!Big>) -> i64
    %x3 = idr.call @firstBig(%b3) : (!idr.box<!Big>) -> i64
    %x4 = idr.call @firstBig(%b4) : (!idr.box<!Big>) -> i64
    %s1 = arith.addi %x0, %x1 : i64
    %s2 = arith.addi %s1, %x2 : i64
    %s3 = arith.addi %s2, %x3 : i64
    %s4 = arith.addi %s3, %x4 : i64
    return %s4 : i64
  }
  // recursive n = if n == 0 then 0 else head [n] + head [n] + head [n] + recursive (n - 1)
  idr.func @recursive(%a: i64, %t: !idr.box<!List>) -> i64 {
    %c0 = idr.con !idr.box<!List> @Cons(%a : i64, %t : !idr.box<!List>)
    %c1 = idr.con !idr.box<!List> @Cons(%a : i64, %t : !idr.box<!List>)
    %c2 = idr.con !idr.box<!List> @Cons(%a : i64, %t : !idr.box<!List>)
    %r = idr.match_lit %a : i64 -> (i64) {
    case 0 {
      idr.yield %a : i64
    }
    default {
      %x0 = idr.call @head(%c0) : (!idr.box<!List>) -> i64
      %x1 = idr.call @head(%c1) : (!idr.box<!List>) -> i64
      %x2 = idr.call @head(%c2) : (!idr.box<!List>) -> i64
      %one = arith.constant 1 : i64
      %m = arith.subi %a, %one : i64
      %rest = idr.call @recursive(%m, %t) : (i64, !idr.box<!List>) -> i64
      %s1 = arith.addi %x0, %x1 : i64
      %s2 = arith.addi %s1, %x2 : i64
      %s3 = arith.addi %s2, %rest : i64
      idr.yield %s3 : i64
    }
    }
    return %r : i64
  }
  idr.func @head(%l: !idr.box<!List>) -> i64 {
    %r = idr.match %l : !idr.box<!List> -> (i64) {
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      idr.yield %h : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
