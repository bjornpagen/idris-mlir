// RUN: idris-mlir-opt %s --idr-expect=holds=constant-stack=@loop,constant-stack=@ping -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=constant-stack=@grows,constant-stack=@there -verify-diagnostics -o /dev/null
// A recursion keeps the stack constant when each call back is a guaranteed
// tail call, which replaces its caller's frame (@loop); a call back that
// keeps the frame grows it with every step (@grows). So with a cycle of
// two: @ping and @pong call each other by musttail, and the stack stays;
// @there calls @back by musttail, but @back calls it back with a frame of
// its own, and a run of @there grows the stack at every second step: the
// error names the cycle. A lowered module, of llvm.func, where musttail
// is written; the contracts hold every compilation's to it.
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
  // expected-error @below {{expected constant-stack: }}
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
  llvm.func tailcc @ping(%x: i64) -> i64 {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %done = llvm.icmp "eq" %x, %zero : i64
    llvm.cond_br %done, ^stop, ^more
  ^more:
    %one = llvm.mlir.constant(1 : i64) : i64
    %y = llvm.sub %x, %one : i64
    %r = llvm.call tailcc musttail @pong(%y) : (i64) -> i64
    llvm.return %r : i64
  ^stop:
    llvm.return %x : i64
  }
  llvm.func tailcc @pong(%x: i64) -> i64 {
    %r = llvm.call tailcc musttail @ping(%x) : (i64) -> i64
    llvm.return %r : i64
  }
  llvm.func tailcc @there(%x: i64) -> i64 {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %done = llvm.icmp "eq" %x, %zero : i64
    llvm.cond_br %done, ^stop, ^more
  ^more:
    %one = llvm.mlir.constant(1 : i64) : i64
    %y = llvm.sub %x, %one : i64
    %r = llvm.call tailcc musttail @back(%y) : (i64) -> i64
    llvm.return %r : i64
  ^stop:
    llvm.return %x : i64
  }
  // expected-error @below {{expected constant-stack: the stack grows with the recursion of @back}}
  llvm.func tailcc @back(%x: i64) -> i64 {
    %r = llvm.call tailcc @there(%x) : (i64) -> i64
    %one = llvm.mlir.constant(1 : i64) : i64
    %s = llvm.add %r, %one : i64
    llvm.return %s : i64
  }
  llvm.func @main() -> i64 {
    %n = llvm.mlir.constant(7 : i64) : i64
    %a = llvm.call tailcc @loop(%n) : (i64) -> i64
    %b = llvm.call @grows(%a) : (i64) -> i64
    %c = llvm.call tailcc @ping(%b) : (i64) -> i64
    %d = llvm.call tailcc @there(%c) : (i64) -> i64
    llvm.return %d : i64
  }
}
