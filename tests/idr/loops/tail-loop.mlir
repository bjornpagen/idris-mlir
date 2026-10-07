// RUN: idris-mlir-opt %s --idr-tail-loops -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@count,constant-stack=@upto,constant-stack=@spin,constant-stack=@sum,constant-stack=@echo -o /dev/null
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=counted-loop=@upto,counted-loop=@until -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=counted-loop=@count -o /dev/null 2> %t.count.err
// RUN: FileCheck %s --check-prefix=COUNT < %t.count.err
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@fib -o /dev/null 2> %t.fib.err
// RUN: FileCheck %s --check-prefix=FIB < %t.fib.err
// RUN: idris-mlir-opt %t.mlir --inline --canonicalize | FileCheck %s --check-prefix=KEPT
// A self tail call in a region of a match whose results are returned
// becomes a loop, so the stack stays constant; a call that is not in tail
// position stays, and the stack grows with it. A loop that counts up to a
// bound becomes an scf.for, whether or not its result is the counter; one
// that counts down to zero keeps its test against zero, and is an
// scf.while.
// COUNT: error: expected counted-loop: a loop of @count has no trip count
// FIB: error: expected constant-stack: the stack grows with the recursion of @fib
// A partial function's loop keeps idr.may_loop, which keeps it alive when
// nothing uses its result; a total one's is dead code once inlined there.
// KEPT-LABEL: func.func @Main.main(
// KEPT: idr.may_loop
// KEPT-NOT: idr.may_loop
// KEPT: call @fib
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  func.func private @count(%acc: i64, %n: i64) -> i64 attributes {idr.total} {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %a = arith.addi %acc, %c1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = func.call @count(%a, %m) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // upto i n acc = if i < n then upto (i + 1) n (acc + i * i) else acc
  func.func private @upto(%i: i64, %n: i64, %acc: i64) -> i64 attributes {idr.total} {
    %lt = arith.cmpi slt, %i, %n : i64
    %b = arith.extui %lt : i1 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      idr.yield %acc : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %j = arith.addi %i, %c1 : i64
      %sq = arith.muli %i, %i : i64
      %a = arith.addi %acc, %sq : i64
      %x = func.call @upto(%j, %n, %a) : (i64, i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // until i n = if i < n then until (i + 3) n else i
  func.func private @until(%i: i64, %n: i64) -> i64 attributes {idr.total} {
    %lt = arith.cmpi slt, %i, %n : i64
    %b = arith.extui %lt : i1 to i64
    %r = idr.match_lit %b : i64 -> (i64) {
    case 0 {
      idr.yield %i : i64
    }
    default {
      %c3 = arith.constant 3 : i64
      %j = arith.addi %i, %c3 : i64
      %x = func.call @until(%j, %n) : (i64, i64) -> i64
      idr.yield %x : i64
    }
    }
    return %r : i64
  }
  // spin x = spin (x + 1)
  func.func private @spin(%x: i64) -> i64 {
    %c1 = arith.constant 1 : i64
    %y = arith.addi %x, %c1 : i64
    %r = func.call @spin(%y) : (i64) -> i64
    return %r : i64
  }
  // sum acc (x :: xs) = sum (acc + x) xs
  func.func private @sum(%acc: i64, %xs: !idr.box<@List>) -> i64 attributes {idr.total} {
    %r = idr.match %xs : !idr.box<@List> -> (i64) {
    case @Nil() {
      idr.yield %acc : i64
    }
    case @Cons(%x: i64, %rest: !idr.box<@List>) {
      %a = arith.addi %acc, %x : i64
      %s = func.call @sum(%a, %rest) : (i64, !idr.box<@List>) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  // echo n = do printLn n; if n == 0 then pure () else echo (n - 1): what
  // the body computes before the decision, the world, goes round too.
  func.func private @echo(%n: i64, %w: !idr.world) -> !idr.world attributes {idr.total} {
    %w1 = idr.io.put_int signed %n, %w : i64
    %r = idr.match_lit %n : i64 -> (!idr.world) {
    case 0 {
      idr.yield %w1 : !idr.world
    }
    default {
      %c1 = arith.constant 1 : i64
      %m = arith.subi %n, %c1 : i64
      %x = func.call @echo(%m, %w1) : (i64, !idr.world) -> !idr.world
      idr.yield %x : !idr.world
    }
    }
    return %r : !idr.world
  }
  func.func private @fib(%n: i64) -> i64 {
    %r = idr.match_lit %n : i64 -> (i64) {
    case 0 {
      idr.yield %n : i64
    }
    case 1 {
      idr.yield %n : i64
    }
    default {
      %c1 = arith.constant 1 : i64
      %c2 = arith.constant 2 : i64
      %a = arith.subi %n, %c1 : i64
      %b = arith.subi %n, %c2 : i64
      %x = func.call @fib(%a) : (i64) -> i64
      %y = func.call @fib(%b) : (i64) -> i64
      %s = arith.addi %x, %y : i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  func.func @Main.main(%w: !idr.world) -> (i64, i64, i64, !idr.world) {
    %nil = idr.con @List::@Nil() : () -> !idr.box<@List>
    %c7 = arith.constant 7 : i64
    %xs = idr.con @List::@Cons(%c7, %nil) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %c0 = arith.constant 0 : i64
    %c9 = arith.constant 9 : i64
    %a = func.call @count(%c0, %c9) : (i64, i64) -> i64
    %u = func.call @upto(%c0, %c9, %c0) : (i64, i64, i64) -> i64
    %b = func.call @spin(%c0) : (i64) -> i64
    %s = func.call @sum(%c0, %xs) : (i64, !idr.box<@List>) -> i64
    %w1 = func.call @echo(%c9, %w) : (i64, !idr.world) -> !idr.world
    %c = func.call @fib(%c9) : (i64) -> i64
    return %u, %s, %c, %w1 : i64, i64, i64, !idr.world
  }
}
