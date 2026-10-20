// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --idr-accumulate --mlir-disable-threading -mlir-debug-counter=idr-accumulate-countdown-count=0,idr-accumulate-clone-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --idr-accumulate -o %t.done.mlir
// RUN: %status 1 diff %t.none.mlir %t.done.mlir
// RUN: %differential %s %t.done.mlir
// With every action skipped the pass is the identity, and with none it
// changes the module. The root runs every function on the natural the
// byte it reads is, and the program prints after the pass what it printed
// before, on every byte.
!List = !idr.data<"List">
#types = #idr.types<
  "List" = list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]
>
idr.program @accumulate root(@root) stage(first) types #types {

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
    %one = idr.constant !idr.nat #idr.big<1>
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %one : !idr.nat
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
  // The list n-1, ..., 1, 0.
  idr.func @build(%n: !idr.nat) -> !idr.box<!List> attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.box<!List>) {
    case #idr.big<0> {
      %nil = idr.con !idr.box<!List> @Nil()
      idr.yield %nil : !idr.box<!List>
    }
    default(%d8: !idr.nat) {
      %p = idr.big.pred %n
      %t = idr.call @build(%p) : (!idr.nat) -> !idr.box<!List>
      %b = idr.nat.to_big %p
      %x = idr.big.to_int %b : i64
      %l = idr.con !idr.box<!List> @Cons(%x : i64, %t : !idr.box<!List>)
      idr.yield %l : !idr.box<!List>
    }
    }
    return %r : !idr.box<!List>
  }
  idr.func @put_nat(%n: !idr.nat, %w: !idr.world) -> !idr.world {
    %b = idr.nat.to_big %n
    %s = idr.big.show %b
    %w1 = idr.io.put_str %s, %w
    %sp = arith.constant 32 : i32
    %w2 = idr.io.put_char %sp, %w1
    return %w2 : !idr.world
  }
  // The program's root runs every function above on the natural the byte
  // it reads is, and on a list that long; @both, which calls itself twice
  // at each step, on that natural modulo 16.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %c15 = arith.constant 15 : i32
    %low = arith.andi %ch, %c15 : i32
    %n = idr.big.from_uint %ch : i32 : !idr.nat
    %m = idr.big.from_uint %low : i32 : !idr.nat
    %three = idr.constant !idr.nat #idr.big<3>
    %zero = idr.constant !idr.nat #idr.big<0>
    %xs = idr.call @build(%n) : (!idr.nat) -> !idr.box<!List>
    %a = idr.call @length(%xs) : (!idr.box<!List>) -> !idr.nat
    %w1 = idr.call @put_nat(%a, %w0) : (!idr.nat, !idr.world) -> !idr.world
    %b = idr.call @steps(%three, %n) : (!idr.nat, !idr.nat) -> !idr.nat
    %w2 = idr.call @put_nat(%b, %w1) : (!idr.nat, !idr.world) -> !idr.world
    %c = idr.call @count(%n, %zero) : (!idr.nat, !idr.nat) -> !idr.nat
    %w3 = idr.call @put_nat(%c, %w2) : (!idr.nat, !idr.world) -> !idr.world
    %d = idr.call @both(%m) : (!idr.nat) -> !idr.nat
    %w4 = idr.call @put_nat(%d, %w3) : (!idr.nat, !idr.world) -> !idr.world
    %e = idr.call @depth(%xs) : (!idr.box<!List>) -> !idr.nat
    %w5 = idr.call @put_nat(%e, %w4) : (!idr.nat, !idr.world) -> !idr.world
    %f = idr.call @down(%n) : (!idr.nat) -> !idr.nat
    %w6 = idr.call @put_nat(%f, %w5) : (!idr.nat, !idr.world) -> !idr.world
    %g = idr.call @twos(%n) : (!idr.nat) -> !idr.nat
    %w7 = idr.call @put_nat(%g, %w6) : (!idr.nat, !idr.world) -> !idr.world
    %h = idr.call @down_out(%n) : (!idr.nat) -> !idr.nat
    %w8 = idr.call @put_nat(%h, %w7) : (!idr.nat, !idr.world) -> !idr.world
    %i = idr.call @as_integer(%n) : (!idr.nat) -> !idr.big
    %s = idr.big.show %i
    %w9 = idr.io.put_str %s, %w8
    return %w9 : !idr.world
  }
}
