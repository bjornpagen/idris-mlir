// NEEDS-ACCEPTANCE: that constant-stack and tail-calls hold of @loop, which calls itself back by a musttail call alone, and fail once each where a call keeps its frame or none is made.
// RUN: idris-mlir-opt %s --idr-expect=holds=constant-stack=@loop,tail-calls=@loop:@loop -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=constant-stack=@grows,tail-calls=@grows:@grows,tail-calls=@loop:@grows -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 3
// A recursion keeps the stack constant when each call back is a guaranteed
// tail call, which replaces its caller's frame (@loop); a call back that
// keeps the frame grows it with every step (@grows). A lowered module, of
// llvm.func, where musttail is written.
// CHECK-DAG: error: expected constant-stack: the stack grows with the recursion of @grows
// CHECK-DAG: error: expected tail-calls: @grows calls {{.*}} and keeps its frame
// CHECK-DAG: error: expected tail-calls: @loop makes no call of {{.*}}
module {
  llvm.func tailcc @loop(%x: i64) -> i64 {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %done = llvm.icmp "eq" %x, %zero : i64
    llvm.cond_br %done, ^stop, ^more
  ^more:
    %one = llvm.mlir.constant(1 : i64) : i64
    %y = llvm.sub %x, %one : i64
    %r = llvm.call tailcc musttail @loop(%y) : (i64) -> i64
    llvm.return %r : i64
  ^stop:
    llvm.return %x : i64
  }
  llvm.func @grows(%x: i64) -> i64 {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %done = llvm.icmp "eq" %x, %zero : i64
    llvm.cond_br %done, ^stop, ^more
  ^more:
    %one = llvm.mlir.constant(1 : i64) : i64
    %y = llvm.sub %x, %one : i64
    %r = llvm.call @grows(%y) : (i64) -> i64
    %s = llvm.add %r, %one : i64
    llvm.return %s : i64
  ^stop:
    llvm.return %x : i64
  }
  llvm.func @main() -> i64 {
    %n = llvm.mlir.constant(7 : i64) : i64
    %a = llvm.call tailcc @loop(%n) : (i64) -> i64
    %b = llvm.call @grows(%a) : (i64) -> i64
    llvm.return %b : i64
  }
}
