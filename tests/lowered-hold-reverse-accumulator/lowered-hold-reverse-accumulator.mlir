// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded})' -o /dev/null
// A copy keyed to a weaker hold for a parameter that reaches its result on
// some paths only returns that hold. @reverseOnto is base's, with a count
// it may wait first: it moves its vector onto its accumulator, which claims
// its own cells, so its result, a vector at the sum of the two lengths,
// claims them too. Its accumulator is its result on the path that ends,
// where the vector is empty, and only part of it on every other, where it
// gives what its own call gives after consing the vector's head onto the
// accumulator: so it gives back nothing on every path, and the accumulator
// may reach its result. Three strings in place hold references; laid out
// at a length unknown at compile time, the same vector is a cell. @made is
// declared to give a vector at its own length, counted and claiming its
// own cells, but where it assumes the length is 3 it re-packs what
// @unknown gives (a vector at a length the index language cannot express,
// `_`, claiming nothing) into three strings in place and casts those to its
// own length: that tail cannot agree with a result laid out at the
// function's own length, so the result is laid out open, at the hold that
// tail gives, which claims nothing. @g calls @made at length 3, and the
// cast after the call gives what @made now returns, claiming nothing,
// which @g passes to @reverseOnto as its accumulator, with a vector of 1.
// So @reverseOnto's copy at 3 and 1 is keyed to the weaker hold for its
// accumulator, and since the accumulator may reach its result, its result
// is keyed to that hold too, and @g takes it so when @g is taken up,
// before the copy exists: what @g makes of it claims nothing (the call to
// @count takes a copy keyed to that hold), and where it joins @g's own tail
// call, whose result still claims the vector's cells, that result is
// shared down, which keeps the tail call; @g's result takes the hold its
// return now gives, and every call of @g with it. The copy at 3 and 1
// conses onto the weaker accumulator, which claims nothing then, and calls
// the copy at 4 and 0 keyed to that hold, whose result is its accumulator
// at that hold: had the copy's result been keyed by what is given back on
// every path alone, it would claim more than it gives. The module verifies
// as written and after every pass to the graded stage, where every call's
// types are its callee's and every tail fact is checked against where its
// call stands. @made and @count read the length of their vector's head and
// @reverseOnto reads its vector, so none leaves its vector unread; each
// function may run for ever, so no call of it is deleted. Each function
// recurses, so each stays a function wherever another is inlined into it,
// and @main calls each where no tail is lost, so each returns to more than
// one place and none becomes a join point of its one tail caller.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (!idr.str, !idr.self[v0])
  }>
!Str = !idr.graded<many, static, !idr.str>
!Unknown = !idr.data<#Vect[_]>
!UnknownNil = !idr.data<#Vect[_] @Nil>
!Vn = !idr.data<#Vect[v0]>
!VnNil = !idr.data<#Vect[v0] @Nil>
!VnCons = !idr.data<#Vect[v0] @Cons<v1>>
!Xs = !idr.data<#Vect[v1]>
!XsNil = !idr.data<#Vect[v1] @Nil>
!XsCons = !idr.data<#Vect[v1] @Cons<v2>>
!Tail = !idr.data<#Vect[v2]>
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
!Claimed = !idr.graded<many, counted unique self, !idr.data<#Vect[v0]>>
!Claimed3 = !idr.graded<many, counted unique self, !idr.data<#Vect[3]>>
!Claimed4 = !idr.graded<many, counted unique self, !idr.data<#Vect[4]>>
!Grown = !idr.graded<many, counted unique self, !idr.data<#Vect[v0 + 1]>>
!Moved = !idr.graded<many, counted unique self, !idr.data<#Vect[v0 + v2 + 1]>>
!Both = !idr.graded<many, counted unique self, !idr.data<#Vect[v0 + v1]>>
idr.program @reversal root(@main) stage(first) {
  idr.func @main() {
    %s = idr.constant !Str "s"
    %nil = idr.data.con() : !V0
    %v1 = idr.data.con(%s : !Str, %nil : !V0) : !V1
    %v2 = idr.data.con(%s : !Str, %v1 : !V1) : !V2
    %v3 = idr.data.con(%s : !Str, %v2 : !V2) : !V3
    %seed = idr.data.con() : !UnknownNil
    %xs = idr.data.reindex %seed : !UnknownNil to !Unknown
    %k = arith.constant 2 : i64
    %u = idr.call @unknown(%xs, %k) <{tail_kind = nontail}> : (!Unknown, i64) -> !Unknown
    %a = idr.call @made(%v3, %xs, %k) <{index_args = #idr.index_args<[3]>, tail_kind = nontail}> : (!V3, !Unknown, i64) -> !Claimed3
    %r = idr.call @reverseOnto(%a, %v1, %k) <{index_args = #idr.index_args<[3, 1]>, tail_kind = nontail}> : (!Claimed3, !V1, i64) -> !Claimed4
    %n = idr.call @count(%r, %k) <{tail_kind = nontail}> : (!Claimed4, i64) -> i64
    %b = idr.call @g(%v3, %xs, %v1, %k) <{tail_kind = nontail}> : (!V3, !Unknown, !V1, i64) -> !Claimed4
    %c = idr.call @g(%v3, %xs, %v1, %n) <{tail_kind = nontail}> : (!V3, !Unknown, !V1, i64) -> !Claimed4
    idr.return
  }
  idr.func @unknown(%xs: !Unknown, %k: i64) -> !Unknown {
    %r = idr.lit.match %k : i64 -> (!Unknown) {
    case 0(%key: i64) {
      idr.yield %xs : !Unknown
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %v = idr.call @unknown(%xs, %j) <{tail_kind = tail}> : (!Unknown, i64) -> !Unknown
      idr.yield %v : !Unknown
    }
    }
    idr.return %r : !Unknown
  } loc("unknown")
  idr.func <{binders = #idr.index_binders<[nat]>}> @made(%ys: !Vn, %xs: !Unknown, %k: i64) -> !Claimed {
    %r = idr.lit.match %k : i64 -> (!Claimed) {
    case 0(%key0: i64) {
      %len = idr.data.match %ys : !Vn -> (i64) {
      case @Nil(%none: !VnNil) {
        idr.yield %key0 : i64
      }
      case @Cons(%cell: !VnCons) {
        %h = idr.data.field %cell[0] : !VnCons -> !idr.str
        %l = idr.str.length %h : (!idr.str) -> i64
        idr.yield %l : i64
      }
      }
      %three = idr.index.assume #idr.equation<v0 = 3> () -> (!Claimed) {
        %u = idr.call @unknown(%xs, %len) <{tail_kind = nontail}> : (!Unknown, i64) -> !Unknown
        %w = idr.data.reindex %u : !Unknown to !V3
        %c = idr.data.reindex %w : !V3 to !Claimed
        idr.yield %c : !Claimed
      }
      idr.yield %three : !Claimed
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.call @made(%ys, %xs, %j) <{index_args = #idr.index_args<[v0]>, tail_kind = tail}> : (!Vn, !Unknown, i64) -> !Claimed
      idr.yield %again : !Claimed
    }
    }
    idr.return %r : !Claimed
  } loc("made")
  idr.func <{binders = #idr.index_binders<[nat, nat]>}> @reverseOnto(%acc: !Claimed, %xs: !Xs, %k: i64) -> !Both {
    %r = idr.lit.match %k : i64 -> (!Both) {
    case 0(%key0: i64) {
      %step = idr.data.match %xs : !Xs -> (!Both) {
      case @Nil(%none: !XsNil) {
        %back = idr.data.reindex %acc : !Claimed to !Both
        idr.yield %back : !Both
      }
      case @Cons(%cell: !XsCons) {
        %h = idr.data.field %cell[0] : !XsCons -> !idr.str
        %t = idr.data.field %cell[1] : !XsCons -> !Tail
        %grown = idr.data.con(%h : !idr.str, %acc : !Claimed) : !Grown
        %s = idr.call @reverseOnto(%grown, %t, %k) <{index_args = #idr.index_args<[v0 + 1, v2]>, tail_kind = tail}> : (!Grown, !Tail, i64) -> !Moved
        %back = idr.data.reindex %s : !Moved to !Both
        idr.yield %back : !Both
      }
      }
      idr.yield %step : !Both
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.call @reverseOnto(%acc, %xs, %j) <{index_args = #idr.index_args<[v0, v1]>, tail_kind = tail}> : (!Claimed, !Xs, i64) -> !Both
      idr.yield %again : !Both
    }
    }
    idr.return %r : !Both
  } loc("reverseOnto")
  idr.func @g(%ys: !V3, %xs: !Unknown, %one: !V1, %k: i64) -> !Claimed4 {
    %r = idr.lit.match %k : i64 -> (!Claimed4) {
    case 0(%key0: i64) {
      %v = idr.call @made(%ys, %xs, %k) <{index_args = #idr.index_args<[3]>, tail_kind = nontail}> : (!V3, !Unknown, i64) -> !Claimed3
      %w = idr.call @reverseOnto(%v, %one, %k) <{index_args = #idr.index_args<[3, 1]>, tail_kind = nontail}> : (!Claimed3, !V1, i64) -> !Claimed4
      %n = idr.call @count(%w, %k) <{tail_kind = nontail}> : (!Claimed4, i64) -> i64
      idr.yield %w : !Claimed4
    }
    default(%d: i64) {
      %step = arith.constant 1 : i64
      %j = arith.subi %d, %step : i64
      %again = idr.call @g(%ys, %xs, %one, %j) <{tail_kind = tail}> : (!V3, !Unknown, !V1, i64) -> !Claimed4
      idr.yield %again : !Claimed4
    }
    }
    idr.return %r : !Claimed4
  } loc("g")
  idr.func @count(%v: !Claimed4, %k: i64) -> i64 {
    %r = idr.lit.match %k : i64 -> (i64) {
    case 0(%key: i64) {
      %h = idr.data.field %v[0] : !Claimed4 -> !idr.str
      %l = idr.str.length %h : (!idr.str) -> i64
      idr.yield %l : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %s = idr.call @count(%v, %j) <{tail_kind = tail}> : (!Claimed4, i64) -> i64
      idr.yield %s : i64
    }
    }
    idr.return %r : i64
  } loc("count")
}
