// RUN: awk '/^ *\/\/ CHAIN$/ { for (i = 1; i < 5000; i++) printf "  ^c%d:\n    llvm.br ^c%d\n", i, i + 1; printf "  ^c5000:\n    llvm.return %%r : i64\n"; next } { print }' %s > %t.long.mlir
// RUN: idris-mlir-opt %t.long.mlir --idr-target --idr-tail-calls --idr-expect=holds=constant-stack=@ping -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.long.mlir --idr-target --idr-tail-calls --idr-expect=holds=constant-stack=@loops -o /dev/null
// NEEDS-ACCEPTANCE: that a call whose path to the return crosses 5,000 blocks is a guaranteed tail call, and one whose path comes back to a block knowing what it knew there before is none.
// Whether a call is in tail position is read along the one path from it
// to a return: a path that comes back to a block knowing what it knew
// there before (the block's arguments and every value live into it) loops,
// and never returns the call's result. So how long the path is decides
// nothing (decided-loops.mlir goes round loops its constants end). The first RUN line writes, where
// the CHAIN line stands, 5,000 blocks that each branch to the next, the
// last returning @ping's call of @pong: a tail call however far its return
// is, so @ping and @pong, on one cycle, call each other in constant stack.
// @loops calls @spins and then branches to a block that branches to
// itself: the call is no tail call, and @loops grows the stack with each
// call of the cycle it is on.
module {
  llvm.func @ping(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %done = llvm.icmp "eq" %x, %zero : i64
    llvm.cond_br %done, ^stop, ^more
  ^stop:
    llvm.return %x : i64
  ^more:
    %one = llvm.mlir.constant(1 : i64) : i64
    %y = llvm.sub %x, %one : i64
    %r = llvm.call @pong(%y) : (i64) -> i64
    llvm.br ^c1
  // CHAIN
  }
  llvm.func @pong(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %r = llvm.call @ping(%x) : (i64) -> i64
    llvm.return %r : i64
  }
  llvm.func @loops(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %zero = llvm.mlir.constant(0 : i64) : i64
    %done = llvm.icmp "eq" %x, %zero : i64
    llvm.cond_br %done, ^stop, ^more
  ^stop:
    llvm.return %x : i64
  ^more:
    %r = llvm.call @spins(%x) : (i64) -> i64
    llvm.br ^again
  ^again:
    llvm.br ^again
  }
  llvm.func @spins(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    %one = llvm.mlir.constant(1 : i64) : i64
    %y = llvm.sub %x, %one : i64
    %r = llvm.call @loops(%y) : (i64) -> i64
    llvm.return %r : i64
  }
  llvm.func @main(%x: i64) -> i64 {
    %a = llvm.call @ping(%x) : (i64) -> i64
    %b = llvm.call @loops(%a) : (i64) -> i64
    llvm.return %b : i64
  }
}
