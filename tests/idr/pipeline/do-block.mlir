// RUN: idris-mlir-opt %s --idr-simplify --remarks-filter-passed=idr-simplify > %t.mlir 2> %t.err
// RUN: FileCheck %s < %t.mlir
// RUN: FileCheck %s --check-prefix=ROUNDS < %t.err
// A do block of 16 statements, in the shape Emit gives it: statement k is
// @sk, the thunk `putStr "k" >> rest` that `>>` delays, whose action is
// @bind of @put and of @seq, which forces the thunk of the next statement.
// Unfolding it takes an inliner iteration per statement, each after the
// canonicalization that turns the apply of the next thunk into a call.
// The inliner iterates until it inlines nothing, so the whole block
// unfolds in one round, not one statement or two per round: the loop ends
// within three rounds, however long the block.
// CHECK-LABEL: func.func @Main.main(
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK: idr.io.put_str
// CHECK-NOT: idr.io.put_str
// CHECK-NOT: func.call
// ROUNDS: fixpoint: round {{[1-3]}} changed nothing
module attributes {idr.program} {
  idr.data @Unit {
    idr.ctor @MkUnit tag 0 () {quantities = []}
  }
  idr.data @IORes {
    idr.ctor @MkIORes tag 0 (!idr.data<@Unit>, !idr.world) {quantities = ["w", "1"]}
  }
  idr.data @IO {
    idr.ctor @MkIO tag 0 (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) {quantities = ["1"]}
  }
  func.func private @put(%s: !idr.str {idr.quantity = "w"}, %w: !idr.world {idr.quantity = "1"}) -> !idr.data<@IORes> attributes {idr.total} {
    %w1 = idr.io.put_str %s, %w
    %u = idr.con @Unit::@MkUnit() : () -> !idr.data<@Unit>
    %r = idr.con @IORes::@MkIORes(%u, %w1) : (!idr.data<@Unit>, !idr.world) -> !idr.data<@IORes>
    return %r : !idr.data<@IORes>
  }
  func.func private @done(%w: !idr.world {idr.quantity = "1"}) -> !idr.data<@IORes> attributes {idr.total} {
    %u = idr.con @Unit::@MkUnit() : () -> !idr.data<@Unit>
    %r = idr.con @IORes::@MkIORes(%u, %w) : (!idr.data<@Unit>, !idr.world) -> !idr.data<@IORes>
    return %r : !idr.data<@IORes>
  }
  // io_bind: runs %a, applies %k to its value and runs the action that gives.
  func.func private @bind(%a: !idr.fn<(!idr.world) -> (!idr.data<@IORes>)> {idr.quantity = "1"}, %k: !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)> {idr.quantity = "1"}, %w: !idr.world {idr.quantity = "1"}) -> !idr.data<@IORes> attributes {idr.total} {
    %r = idr.apply %a(%w) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %u = idr.field %r[@MkIORes, 0] : !idr.data<@IORes> -> !idr.data<@Unit>
    %w1 = idr.field %r[@MkIORes, 1] : !idr.data<@IORes> -> !idr.world
    %io = idr.apply %k(%u) : !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %f = idr.field %io[@MkIO, 0] : !idr.data<@IO> -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %s = idr.apply %f(%w1) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    return %s : !idr.data<@IORes>
  }
  // The continuation of `>>`: forces the delayed rest of the block.
  func.func private @seq(%rest: !idr.fn<() -> (!idr.data<@IO>)> {idr.quantity = "w"}, %u: !idr.data<@Unit> {idr.quantity = "w"}) -> !idr.data<@IO> attributes {idr.total} {
    %io = idr.apply %rest() : !idr.fn<() -> (!idr.data<@IO>)>
    return %io : !idr.data<@IO>
  }
  func.func private @s1() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "1\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s2() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s2() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "2\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s3() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s3() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "3\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s4() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s4() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "4\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s5() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s5() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "5\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s6() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s6() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "6\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s7() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s7() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "7\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s8() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s8() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "8\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s9() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s9() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "9\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s10() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s10() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "10\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s11() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s11() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "11\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s12() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s12() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "12\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s13() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s13() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "13\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s14() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s14() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "14\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s15() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s15() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "15\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %t = idr.closure @s16() : () -> !idr.fn<() -> (!idr.data<@IO>)>
    %c = idr.closure @seq(%t) : (!idr.fn<() -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %c) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @s16() -> !idr.data<@IO> attributes {idr.total} {
    %str = idr.constant "16\0A" : !idr.str
    %p = idr.closure @put(%str) : (!idr.str) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %d = idr.closure @done() : () -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %e = idr.con @IO::@MkIO(%d) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    %t = idr.closure @const(%e) : (!idr.data<@IO>) -> !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>
    %b = idr.closure @bind(%p, %t) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>, !idr.fn<(!idr.data<@Unit>) -> (!idr.data<@IO>)>) -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %io = idr.con @IO::@MkIO(%b) : (!idr.fn<(!idr.world) -> (!idr.data<@IORes>)>) -> !idr.data<@IO>
    return %io : !idr.data<@IO>
  }
  func.func private @const(%io: !idr.data<@IO> {idr.quantity = "w"}, %u: !idr.data<@Unit> {idr.quantity = "w"}) -> !idr.data<@IO> attributes {idr.total} {
    return %io : !idr.data<@IO>
  }
  func.func @Main.main(%w: !idr.world {idr.quantity = "1"}) -> !idr.data<@IORes> attributes {idr.total} {
    %io = func.call @s1() : () -> !idr.data<@IO>
    %f = idr.field %io[@MkIO, 0] : !idr.data<@IO> -> !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    %r = idr.apply %f(%w) : !idr.fn<(!idr.world) -> (!idr.data<@IORes>)>
    return %r : !idr.data<@IORes>
  }
}
