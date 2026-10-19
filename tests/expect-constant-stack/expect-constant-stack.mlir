// RUN: idris-mlir-opt %s --idr-expect=holds=constant-stack=@loop,tail-calls=@loop:@loop -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=constant-stack=@grows,tail-calls=@grows:@grows,tail-calls=@loop:@grows -verify-diagnostics -o /dev/null
// A recursion keeps the stack constant when each call back is a guaranteed
// tail call, which replaces its caller's frame (@loop); a call back that
// keeps the frame grows it with every step (@grows). A lowered module, of
// llvm.func, where musttail is written.
module {
  // expected-error @below {{expected tail-calls: }}
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
  // expected-error @below {{expected constant-stack: }}
  llvm.func @grows(%x: i64) -> i64 {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %done = llvm.icmp "eq" %x, %zero : i64
    llvm.cond_br %done, ^stop, ^more
  ^more:
    %one = llvm.mlir.constant(1 : i64) : i64
    %y = llvm.sub %x, %one : i64
    // expected-error @below {{expected tail-calls: }}
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
