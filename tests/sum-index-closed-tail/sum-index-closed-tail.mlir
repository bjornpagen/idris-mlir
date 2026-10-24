// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=tail-calls=@later:@reverseOnto,results-as-given=@later:@reverseOnto,results-as-given=@reverseOnto:@reverseOnto})' -o /dev/null
// A length computed from known lengths is known. @reverseOnto is base's,
// with a count it may wait first: it moves its vector onto its
// accumulator, so its result's length is the sum of its two, a term of
// the index language. @later waits, then tail-calls it, at the same two
// lengths. @main calls @later at 0 and 3, twice, so the copy of @later at
// those lengths returns three words in place, since 0 + 3 is 3: a sum whose
// levels became naturals is the natural they add to. So does the copy of
// @reverseOnto it tail-calls: inside it each step's call passes the length
// its match fixed (a cons of 3 has a tail of 2), so it keys the copy at 1
// and 2, whose result is 3 again, down to the copy at 3 and 0, whose empty
// case gives back the accumulator. So every call of @reverseOnto, in
// @later and in each step, gives its result as its callee returns it, with
// no re-pack after it, and @later's is a tail call. Were a step left at a
// length its copy does not know, the call would give a cell its caller
// re-packs in place. As written, a step casts the sum `v0 + v2 + 1` to
// `v0 + v1` under the case's `v1 = v2 + 1`, which the scope rule reads as
// one term, learning nothing of the sum's parts. Each function recurses,
// so each copy stays a function wherever another is inlined into it; and
// @main calls the copy of @later twice and the copy of @reverseOnto at 0
// and 3 itself, each where no tail is lost, so each returns to more than
// one place and neither becomes a join point of its one tail caller, which
// would leave the properties no call to read.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
!Acc = !idr.data<#Vect[v0]>
!Xs = !idr.data<#Vect[v1]>
!Both = !idr.data<#Vect[v0 + v1]>
idr.program @reversal root(@main) stage(first) {
  idr.func @main() {
    %x = arith.constant 7 : i64
    %nil = idr.data.con() : !V0
    %v1 = idr.data.con(%x : i64, %nil : !V0) : !V1
    %v2 = idr.data.con(%x : i64, %v1 : !V1) : !V2
    %v3 = idr.data.con(%x : i64, %v2 : !V2) : !V3
    %k = arith.constant 2 : i64
    %r = idr.call @later(%nil, %v3, %k) <{index_args = #idr.index_args<[0, 3]>}> : (!V0, !V3, i64) -> !V3
    %once = arith.constant 1 : i64
    %s = idr.call @later(%nil, %v3, %once) <{index_args = #idr.index_args<[0, 3]>}> : (!V0, !V3, i64) -> !V3
    %now = arith.constant 0 : i64
    %t = idr.call @reverseOnto(%nil, %v3, %now) <{index_args = #idr.index_args<[0, 3]>}> : (!V0, !V3, i64) -> !V3
    idr.return
  }
  idr.func <{binders = #idr.index_binders<[nat, nat]>}> @later(%acc: !Acc, %xs: !Xs, %k: i64) -> !Both {
    %r = idr.lit.match %k : i64 -> (!Both) {
    case 0(%key0: i64) {
      %moved = idr.tail_call @reverseOnto(%acc, %xs, %k) <{index_args = #idr.index_args<[v0, v1]>}> : (!Acc, !Xs, i64) -> !Both
      idr.yield %moved : !Both
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.tail_call @later(%acc, %xs, %j) <{index_args = #idr.index_args<[v0, v1]>}> : (!Acc, !Xs, i64) -> !Both
      idr.yield %again : !Both
    }
    }
    idr.return %r : !Both
  } loc("later")
  idr.func <{binders = #idr.index_binders<[nat, nat]>}> @reverseOnto(%acc: !Acc, %xs: !Xs, %k: i64) -> !Both {
    %r = idr.lit.match %k : i64 -> (!Both) {
    case 0(%key1: i64) {
      %step = idr.data.match %xs : !Xs -> (!Both) {
      case @Nil(%n: !idr.data<#Vect[v1] @Nil>) {
        %back = idr.data.reindex %acc : !Acc to !Both
        idr.yield %back : !Both
      }
      case @Cons(%c: !idr.data<#Vect[v1] @Cons<v2>>) {
        %h = idr.data.field %c[0] : !idr.data<#Vect[v1] @Cons<v2>> -> i64
        %t = idr.data.field %c[1] : !idr.data<#Vect[v1] @Cons<v2>> -> !idr.data<#Vect[v2]>
        %grown = idr.data.con(%h : i64, %acc : !Acc) : !idr.data<#Vect[v0 + 1]>
        %s = idr.tail_call @reverseOnto(%grown, %t, %k) <{index_args = #idr.index_args<[v0 + 1, v2]>}> : (!idr.data<#Vect[v0 + 1]>, !idr.data<#Vect[v2]>, i64) -> !idr.data<#Vect[v0 + v2 + 1]>
        %back = idr.data.reindex %s : !idr.data<#Vect[v0 + v2 + 1]> to !Both
        idr.yield %back : !Both
      }
      }
      idr.yield %step : !Both
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.tail_call @reverseOnto(%acc, %xs, %j) <{index_args = #idr.index_args<[v0, v1]>}> : (!Acc, !Xs, i64) -> !Both
      idr.yield %again : !Both
    }
    }
    idr.return %r : !Both
  } loc("reverseOnto")
}
