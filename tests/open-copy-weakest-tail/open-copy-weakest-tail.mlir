// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=tail-calls=@f:@g,results-as-given=@f:@g,tail-calls=@h:@g})' -o /dev/null
// A copy keyed open for a tail lost to a layout returns its result at the
// weakest hold its own tails give, and its callers read that hold. @f
// returns a vector of an unknown length, counted and claiming its own
// cells; where it assumes the length is 4 it calls @g, which returns four
// words in place, so as written a re-pack follows the call. The copy of @g
// that @f calls instead returns its vector laid out as @f's is, and gives
// it at each of @g's tails: one builds the four words, which laid out open
// are a fresh cell claiming its own cells; another takes apart a vector
// already laid out open, which @g is given shared, so that tail gives the
// cell as shared as it came. The copy returns its vector at the hold every
// tail fits, the shared one, and @f's result takes it too, so the cast
// after the call builds nothing and gives what @f returns: the module
// verifies after every pass to the graded stage, and the call is a tail
// call that gives its result as its callee returns it.
// @f, @g and @h each recurse, so each stays a function wherever another is
// inlined into it. @h makes the same call of @g as @f, at another count,
// so the copy of @g returns to more than one place and is never a join
// point of its one tail caller; and @main calls @f and @h twice each where
// no tail is lost, so neither is a join point of @main. @main writes out
// the constructors of what each call gives, so no result is left unread.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
!V4 = !idr.data<#Vect[4]>
!Built = !idr.graded<many, counted unique self, !idr.data<#Vect[4] open>>
!Shared = !idr.data<#Vect[4] open>
!Any = !idr.graded<many, counted unique self, !idr.data<#Vect[v0]>>
idr.program @vectors root(@main) stage(first) {
  idr.func <{binders = #idr.index_binders<[nat]>}> @main() {
    %seven = arith.constant 7 : i64
    %nil = idr.data.con() : !V0
    %v1 = idr.data.con(%seven : i64, %nil : !V0) : !V1
    %v2 = idr.data.con(%seven : i64, %v1 : !V1) : !V2
    %v3 = idr.data.con(%seven : i64, %v2 : !V2) : !V3
    %v4 = idr.data.con(%seven : i64, %v3 : !V3) : !V4
    %built = idr.data.reindex %v4 : !V4 to !Built
    %shared = idr.count.share %built : !Built
    %three = arith.constant 3 : i64
    %five = arith.constant 5 : i64
    %a = idr.call @f(%shared, %three) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (!Shared, i64) -> !Any
    %b = idr.call @f(%shared, %five) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (!Shared, i64) -> !Any
    %c = idr.call @h(%shared, %three) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (!Shared, i64) -> !Any
    %d = idr.call @h(%shared, %five) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (!Shared, i64) -> !Any
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
  idr.func <{binders = #idr.index_binders<[nat]>}> @f(%s: !Shared, %n: i64) -> !Any {
    %r = idr.lit.match %n : i64 -> (!Any) {
    case 0(%key0: i64) {
      %four = idr.index.assume #idr.equation<v0 = 4> () -> (!Any) {
        %v = idr.call @g(%s, %n) <{tail_kind = nontail}> : (!Shared, i64) -> !V4
        %c = idr.data.reindex %v : !V4 to !Any
        idr.yield %c : !Any
      }
      idr.yield %four : !Any
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %m = arith.subi %d, %one : i64
      %v = idr.call @f(%s, %m) <{index_args = #idr.index_args<[v0]>, tail_kind = tail}> : (!Shared, i64) -> !Any
      idr.yield %v : !Any
    }
    }
    idr.return %r : !Any
  } loc("f")
  idr.func <{binders = #idr.index_binders<[nat]>}> @h(%s: !Shared, %n: i64) -> !Any {
    %r = idr.lit.match %n : i64 -> (!Any) {
    case 1(%key1: i64) {
      %four = idr.index.assume #idr.equation<v0 = 4> () -> (!Any) {
        %v = idr.call @g(%s, %n) <{tail_kind = nontail}> : (!Shared, i64) -> !V4
        %c = idr.data.reindex %v : !V4 to !Any
        idr.yield %c : !Any
      }
      idr.yield %four : !Any
    }
    default(%d: i64) {
      %two = arith.constant 2 : i64
      %m = arith.subi %d, %two : i64
      %v = idr.call @h(%s, %m) <{index_args = #idr.index_args<[v0]>, tail_kind = tail}> : (!Shared, i64) -> !Any
      idr.yield %v : !Any
    }
    }
    idr.return %r : !Any
  } loc("h")
  idr.func @g(%s: !Shared, %k: i64) -> !V4 {
    %r = idr.lit.match %k : i64 -> (!V4) {
    case 0(%key0: i64) {
      %x = arith.constant 7 : i64
      %nil = idr.data.con() : !V0
      %v1 = idr.data.con(%x : i64, %nil : !V0) : !V1
      %v2 = idr.data.con(%x : i64, %v1 : !V1) : !V2
      %v3 = idr.data.con(%x : i64, %v2 : !V2) : !V3
      %v4 = idr.data.con(%x : i64, %v3 : !V3) : !V4
      idr.yield %v4 : !V4
    }
    case 1(%key1: i64) {
      %w = idr.data.reindex %s : !Shared to !V4
      idr.yield %w : !V4
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %v = idr.call @g(%s, %j) <{tail_kind = tail}> : (!Shared, i64) -> !V4
      idr.yield %v : !V4
    }
    }
    idr.return %r : !V4
  } loc("g")
}
