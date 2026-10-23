// RUN: idris-mlir-opt %s --idr-contracts --test-idr-break-contract=relation=cycle-divergence-kept -verify-diagnostics -o /dev/null
// A cycle of several functions Idris did not prove may run forever, which
// the writer joins into every member's row. No function's check can see
// it: a member's body shows the cycle only through its calls' copies of
// the other members' rows. A pass that drops it from every member and
// from every call of one leaves a module that verifies, and the contracts,
// which run the writer's own rule of cycles over the rows the module
// holds, name the pass: the test pass that breaks cycle-divergence-kept on
// purpose. @down and @up call each other, neither call a tail call, and
// neither has a loop or a call of itself, so the cycle is all that may
// keep either from ending. @main's call of @down loses it too, so the call
// holds its callee's row still; @main's own row keeps it, and says more
// than its body does, which no relation forbids.
idr.program @contracts root(@main) stage(first) {
  idr.func <{row = ["divergence"]}> @main() {
    %n = arith.constant 6 : i64
    %r = idr.call @down(%n) <{row = ["divergence"], tail_kind = nontail}> : (i64) -> i64
    idr.return
  }
  // expected-error @+1 {{contract cycle-divergence-kept broken by}}
  idr.func <{row = ["divergence"]}> @down(%n: i64) -> i64 {
    %r = idr.lit.match %n : i64 -> (i64) {
      case 0(%key0: i64) {
        idr.yield %n : i64
      } default(%d: i64) {
        %one = arith.constant 1 : i64
        %next = arith.subi %d, %one : i64
        %t = idr.call @up(%next) <{row = ["divergence"], tail_kind = nontail}> : (i64) -> i64
        %s = arith.addi %t, %one : i64
        idr.yield %s : i64
      }
    }
    idr.return %r : i64
  }
  // expected-error @+1 {{contract cycle-divergence-kept broken by}}
  idr.func <{row = ["divergence"]}> @up(%n: i64) -> i64 {
    %r = idr.lit.match %n : i64 -> (i64) {
      case 0(%key1: i64) {
        idr.yield %n : i64
      } default(%d: i64) {
        %one = arith.constant 1 : i64
        %next = arith.subi %d, %one : i64
        %t = idr.call @down(%next) <{row = ["divergence"], tail_kind = nontail}> : (i64) -> i64
        %s = arith.addi %t, %one : i64
        idr.yield %s : i64
      }
    }
    idr.return %r : i64
  }
}
