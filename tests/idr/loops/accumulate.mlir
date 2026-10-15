// RUN: idris-mlir-opt %s --idr-accumulate -o %t.acc.mlir
// RUN: FileCheck %s < %t.acc.mlir
// RUN: idris-mlir-opt %t.acc.mlir --idr-accumulate -o %t.again.mlir
// RUN: diff -q %t.acc.mlir %t.again.mlir
// RUN: idris-mlir-opt %t.acc.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@length,constant-stack=@steps,constant-stack=@count})' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.acc.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@both})' -o /dev/null 2> %t.both.err
// RUN: FileCheck %s --check-prefix=BOTH < %t.both.err
// RUN: %status 1 idris-mlir-opt %t.acc.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@depth})' -o /dev/null 2> %t.depth.err
// RUN: FileCheck %s --check-prefix=DEPTH < %t.depth.err
// NEEDS-ACCEPTANCE: the copies are named <owner>.acc.<16 hex digits> from their keys (C21); check that the patterns match them.
// A tail that adds its own result carries the sum. @length adds one,
// @steps adds an argument: each calls a clone with zero and the clone adds
// before the call, which idr-tail-loops makes a loop. @count already adds
// before its call, so it is left to that pass. @both adds two self calls,
// and @depth inspects its result: neither carries a sum, and the stack
// grows with the call.
// CHECK-LABEL: idr.func @length(
// CHECK: %[[Z:.*]] = {{(idr\.)?}}constant #idr.big<0>
// CHECK: %[[R:.*]] = call @{{length\.acc\.[0-9a-f]+}}(%{{[^,]+}}, %[[Z]])
// CHECK: return %[[R]]
// CHECK-LABEL: idr.func @{{length\.acc\.[0-9a-f]+}}(
// CHECK-SAME: %[[ACC:[[:alnum:]_]+]]: !idr.nat)
// CHECK: case @Nil()
// CHECK: idr.yield %[[ACC]]
// CHECK: %[[S:.*]] = idr.big.add %[[ACC]], %{{[^:]+}} : !idr.nat
// CHECK: %[[C:.*]] = {{(idr\.)?}}call @{{length\.acc\.[0-9a-f]+}}(%{{[^,]+}}, %[[S]])
// CHECK: idr.yield %[[C]]
// CHECK-LABEL: idr.func @steps(
// CHECK: call @{{steps\.acc\.[0-9a-f]+}}(
// CHECK-LABEL: idr.func @{{steps\.acc\.[0-9a-f]+}}(
// CHECK: idr.big.add
// CHECK: call @{{steps\.acc\.[0-9a-f]+}}(
// CHECK-NOT: @count.acc
// CHECK-LABEL: idr.func @count(
// CHECK: call @count(
// CHECK-NOT: @both.acc
// CHECK-LABEL: idr.func @both(
// CHECK: call @both(
// CHECK-NOT: @depth.acc
// CHECK-LABEL: idr.func @depth(
// CHECK: call @depth(
// A countdown that adds one from zero is the argument, the sum of that
// many ones. Adding two is the accumulator clone, not the argument.
// CHECK-LABEL: idr.func @down(
// CHECK-SAME: %[[N:[[:alnum:]_]+]]: !idr.nat
// CHECK-NEXT: return %[[N]]
// CHECK-LABEL: idr.func @twos(
// CHECK: call @{{twos\.acc\.[0-9a-f]+}}(
// CHECK-LABEL: idr.func @{{twos\.acc\.[0-9a-f]+}}(
// CHECK: idr.big.add
// The same countdown after simplification has lifted the constants out of
// the branches. A sum of big ones is the argument as an Integer.
// CHECK-LABEL: idr.func @down_out(
// CHECK-SAME: %[[N:[[:alnum:]_]+]]: !idr.nat
// CHECK-NEXT: return %[[N]]
// CHECK-LABEL: idr.func @as_integer(
// CHECK-SAME: %[[N:[[:alnum:]_]+]]: !idr.nat
// CHECK-NEXT: %[[I:.*]] = idr.nat.to_big %[[N]]
// CHECK-NEXT: return %[[I]]
// BOTH: expected constant-stack: the stack grows with the recursion of @both
// DEPTH: expected constant-stack: the stack grows with the recursion of @depth
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
idr.program @accumulate root(@root) stage(first) {

  idr.func @length(%xs: !idr.box<!List>) -> !idr.nat attributes {total} {
    %one = idr.constant #idr.big<1> : !idr.nat
    %zero = idr.constant #idr.big<0> : !idr.nat
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
    %zero = idr.constant #idr.big<0> : !idr.nat
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %zero : !idr.nat
    }
    default {
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
    default {
      %p = idr.big.pred %n
      %one = idr.constant #idr.big<1> : !idr.nat
      %more = idr.big.add %acc, %one : !idr.nat
      %s = idr.call @count(%p, %more) : (!idr.nat, !idr.nat) -> !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @both(%n: !idr.nat) -> !idr.nat attributes {total} {
    %zero = idr.constant #idr.big<0> : !idr.nat
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %zero : !idr.nat
    }
    default {
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
    %zero = idr.constant #idr.big<0> : !idr.nat
    %one = idr.constant #idr.big<1> : !idr.nat
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
      default {
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
      %zero = idr.constant #idr.big<0> : !idr.nat
      idr.yield %zero : !idr.nat
    }
    default {
      %p = idr.big.pred %n
      %c = idr.call @down(%p) : (!idr.nat) -> !idr.nat
      %one = idr.constant #idr.big<1> : !idr.nat
      %s = idr.big.add %c, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @twos(%n: !idr.nat) -> !idr.nat attributes {total} {
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      %zero = idr.constant #idr.big<0> : !idr.nat
      idr.yield %zero : !idr.nat
    }
    default {
      %p = idr.big.pred %n
      %c = idr.call @twos(%p) : (!idr.nat) -> !idr.nat
      %two = idr.constant #idr.big<2> : !idr.nat
      %s = idr.big.add %c, %two : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @down_out(%n: !idr.nat) -> !idr.nat attributes {total} {
    %one = idr.constant #idr.big<1> : !idr.nat
    %zero = idr.constant #idr.big<0> : !idr.nat
    %r = idr.match_lit %n : !idr.nat -> (!idr.nat) {
    case #idr.big<0> {
      idr.yield %zero : !idr.nat
    }
    default {
      %p = idr.big.pred %n
      %c = idr.call @down_out(%p) : (!idr.nat) -> !idr.nat
      %s = idr.big.add %c, %one : !idr.nat
      idr.yield %s : !idr.nat
    }
    }
    return %r : !idr.nat
  }

  idr.func @as_integer(%n: !idr.nat) -> !idr.big attributes {total} {
    %one = idr.constant #idr.big<1> : !idr.big
    %zero = idr.constant #idr.big<0> : !idr.big
    %r = idr.match_lit %n : !idr.nat -> (!idr.big) {
    case #idr.big<0> {
      idr.yield %zero : !idr.big
    }
    default {
      %p = idr.big.pred %n
      %c = idr.call @as_integer(%p) : (!idr.nat) -> !idr.big
      %s = idr.big.add %c, %one : !idr.big
      idr.yield %s : !idr.big
    }
    }
    return %r : !idr.big
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
