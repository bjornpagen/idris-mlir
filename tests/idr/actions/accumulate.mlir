// NEEDS-ACCEPTANCE: that skipping every idr-accumulate-countdown and idr-accumulate-clone action leaves the module as idr-accumulate received it, and that idr-accumulate changes it otherwise.
// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --idr-accumulate --mlir-disable-threading -mlir-debug-counter=idr-accumulate-countdown-count=0,idr-accumulate-clone-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --idr-accumulate -o %t.done.mlir
// RUN: not diff %t.none.mlir %t.done.mlir
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @accumulate root(@root) stage(first) {

  idr.func @length(%xs: !idr.box<!List>) -> !idr.nat attributes {total} {
    %one = idr.constant !idr.nat #idr.big<1>
    %zero = idr.constant !idr.nat #idr.big<0>
    %r = idr.match %xs : !idr.box<!List> -> (!idr.nat) {
    case @Nil() {
      idr.yield %zero : !idr.nat
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %n = idr.call @length(%rest) : (!idr.box<!List>) -> !idr.nat
      %s = idr.big.add %n, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @steps(%k: !idr.nat, %n: !idr.nat) -> !idr.nat attributes {total} {
    %zero = idr.constant !idr.nat #idr.big<0>
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %zero : !idr.nat
    }
    default(%d0: !idr.nat) {
      %p = idr.big.pred %n
      %c = idr.call @steps(%k, %p) : (!idr.nat, !idr.nat) -> !idr.nat
      %s = idr.big.add %c, %k : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @count(%n: !idr.nat, %acc: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %acc : !idr.nat
    }
    default(%d1: !idr.nat) {
      %p = idr.big.pred %n
      %one = idr.constant !idr.nat #idr.big<1>
      %more = idr.big.add %acc, %one : !idr.nat
      %s = idr.call @count(%p, %more) : (!idr.nat, !idr.nat) -> !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @both(%n: !idr.nat) -> !idr.nat attributes {total} {
    %zero = idr.constant !idr.nat #idr.big<0>
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %zero : !idr.nat
    }
    default(%d2: !idr.nat) {
      %p = idr.big.pred %n
      %a = idr.call @both(%p) : (!idr.nat) -> !idr.nat
      %b = idr.call @both(%p) : (!idr.nat) -> !idr.nat
      %s = idr.big.add %a, %b : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @depth(%xs: !idr.box<!List>) -> !idr.nat attributes {total} {
    %zero = idr.constant !idr.nat #idr.big<0>
    %one = idr.constant !idr.nat #idr.big<1>
    %r = idr.match %xs : !idr.box<!List> -> (!idr.nat) {
    case @Nil() {
      idr.yield %zero : !idr.nat
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %n = idr.call @depth(%rest) : (!idr.box<!List>) -> !idr.nat
      %s = idr.match_lit %n : !idr.nat -> (!idr.nat) {
      case #idr.big<0> {
        idr.yield %zero : !idr.nat
      }
      default(%d3: !idr.nat) {
        idr.yield %one : !idr.nat
      }
      }
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @down(%n: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      %zero = idr.constant !idr.nat #idr.big<0>
      idr.yield %zero : !idr.nat
    }
    default(%d4: !idr.nat) {
      %p = idr.big.pred %n
      %c = idr.call @down(%p) : (!idr.nat) -> !idr.nat
      %one = idr.constant !idr.nat #idr.big<1>
      %s = idr.big.add %c, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @twos(%n: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      %zero = idr.constant !idr.nat #idr.big<0>
      idr.yield %zero : !idr.nat
    }
    default(%d5: !idr.nat) {
      %p = idr.big.pred %n
      %c = idr.call @twos(%p) : (!idr.nat) -> !idr.nat
      %two = idr.constant !idr.nat #idr.big<2>
      %s = idr.big.add %c, %two : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @down_out(%n: !idr.nat) -> !idr.nat attributes {total} {
    %one = idr.constant !idr.nat #idr.big<1>
    %zero = idr.constant !idr.nat #idr.big<0>
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %zero : !idr.nat
    }
    default(%d6: !idr.nat) {
      %p = idr.big.pred %n
      %c = idr.call @down_out(%p) : (!idr.nat) -> !idr.nat
      %s = idr.big.add %c, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @as_integer(%n: !idr.nat) -> !idr.big attributes {total} {
    %one = idr.constant !idr.big #idr.big<1>
    %zero = idr.constant !idr.big #idr.big<0>
    %r = idr.match_lit %n : !idr.nat -> (!idr.big) {
    case #idr.big<0> {
      idr.yield %zero : !idr.big
    }
    default(%d7: !idr.nat) {
      %p = idr.big.pred %n
      %c = idr.call @as_integer(%p) : (!idr.nat) -> !idr.big
      %s = idr.big.add %c, %one : !idr.big
      idr.yield %s : !idr.big
    }
    }
    return %r : !idr.big
  }
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
