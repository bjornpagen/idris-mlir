// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=tail-calls=@f:@g,results-as-given=@f:@g})' -o /dev/null
// A tail call whose callee returns a layout its caller does not is made a
// tail call by calling a copy of the callee that returns its caller's
// layout, and the index Idris proved stays in the copy's result. @f returns
// a vector of an unknown length, in a cell; where it assumes its length is
// 4 it calls @g, which returns four words in place, so as written the
// call is followed by a re-pack and is no tail call. The copy of @g it
// calls instead returns its vector marked open, still of length 4 and laid
// out as @f's is: the cast after the call builds nothing, the refinement
// around it still relates the two types, which the verifier holds after
// every pass up to the graded stage, and the call is a tail call that
// gives its result as its callee returns it.
// Four words in place hold no reference, so @g's vector has no hold, and a
// re-pack that builds a cell gives a fresh value, counted and claiming its
// own cells, whatever its operand held: the cast as written relates a
// vector with no hold to one counted and claiming its own cells, and the
// cast after the copy's call, which builds nothing, keeps the hold the
// copy's result has.
// @f and @g each recurse, so each stays a function wherever the other is
// inlined into it. @h makes the same call of @g as @f, at another count, so
// the copy of @g returns to more than one place and is never a join point
// of its one tail caller; and @main calls @f and @h twice each where no
// tail is lost, so neither is a join point of @main. @main writes out the
// constructors of what each call gives, so no result is left unread.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
!V4 = !idr.data<#Vect[4]>
!Any = !idr.graded<many, counted unique self, !idr.data<#Vect[v0]>>
idr.program @vectors root(@main) stage(first) {
  idr.func <{binders = #idr.index_binders<[nat]>}> @main() {
    %three = arith.constant 3 : i64
    %five = arith.constant 5 : i64
    %a = idr.call @f(%three) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (i64) -> !Any
    %b = idr.call @f(%five) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (i64) -> !Any
    %c = idr.call @h(%three) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (i64) -> !Any
    %d = idr.call @h(%five) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (i64) -> !Any
    %ta = idr.data.tag %a : !Any
    %tb = idr.data.tag %b : !Any
    %tc = idr.data.tag %c : !Any
    %td = idr.data.tag %d : !Any
    %ab = arith.addi %ta, %tb : i64
    %cd = arith.addi %tc, %td : i64
    %tags = arith.addi %ab, %cd : i64
    %text = idr.str.show_sint %tags : (i64) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
  idr.func <{binders = #idr.index_binders<[nat]>}> @f(%n: i64) -> !Any {
    %r = idr.lit.match %n : i64 -> (!Any) {
    case 0(%key0: i64) {
      %four = idr.index.assume #idr.equation<v0 = 4> () -> (!Any) {
        %v = idr.call @g(%n) <{tail_kind = nontail}> : (i64) -> !V4
        %c = idr.data.reindex %v : !V4 to !Any
        idr.yield %c : !Any
      }
      idr.yield %four : !Any
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %d, %one : i64
      %v = idr.call @f(%m) <{index_args = #idr.index_args<[v0]>, tail_kind = tail}> : (i64) -> !Any
      idr.yield %v : !Any
    }
    }
    idr.return %r : !Any
  } loc("f")
  idr.func <{binders = #idr.index_binders<[nat]>}> @h(%n: i64) -> !Any {
    %r = idr.lit.match %n : i64 -> (!Any) {
    case 1(%key1: i64) {
      %four = idr.index.assume #idr.equation<v0 = 4> () -> (!Any) {
        %v = idr.call @g(%n) <{tail_kind = nontail}> : (i64) -> !V4
        %c = idr.data.reindex %v : !V4 to !Any
        idr.yield %c : !Any
      }
      idr.yield %four : !Any
    }
    default(%d: i64) {
      %two = arith.constant 2 : i64
      %m = arith.subi %d, %two : i64
      %v = idr.call @h(%m) <{index_args = #idr.index_args<[v0]>, tail_kind = tail}> : (i64) -> !Any
      idr.yield %v : !Any
    }
    }
    idr.return %r : !Any
  } loc("h")
  idr.func @g(%k: i64) -> !V4 {
    %r = idr.lit.match %k : i64 -> (!V4) {
    case 0(%key2: i64) {
      %x = arith.constant 7 : i64
      %nil = idr.data.con() : !V0
      %v1 = idr.data.con(%x : i64, %nil : !V0) : !V1
      %v2 = idr.data.con(%x : i64, %v1 : !V1) : !V2
      %v3 = idr.data.con(%x : i64, %v2 : !V2) : !V3
      %v4 = idr.data.con(%x : i64, %v3 : !V3) : !V4
      idr.yield %v4 : !V4
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %k1 = arith.subi %d, %one : i64
      %v = idr.call @g(%k1) <{tail_kind = tail}> : (i64) -> !V4
      idr.yield %v : !V4
    }
    }
    idr.return %r : !V4
  } loc("g")
}
