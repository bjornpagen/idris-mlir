// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded})' -o /dev/null
// A callee whose result opens to a weaker hold than its callers' types
// claimed gives them less, and each caller's values that carry the result
// are re-graded down where the call stands, never cast back up. Three
// strings in place hold references; laid out at a length unknown at compile
// time, the same vector is a cell. @made is declared to give a vector at
// its own length, counted and claiming its own cells. Where it assumes the
// length is 3, it re-packs what @unknown gives (a vector at a length the
// index language cannot express, as Emit writes `Vect (length xs)`: `_`,
// claiming nothing) into three strings in place and casts those to its own
// length, which builds a fresh cell, claimed unique. That tail cannot agree
// with a result laid out at the function's own length, so the result is
// laid out open, and at the hold that tail gives, which claims nothing:
// what @unknown gives is a cell no one claims. @g calls @made at length 3,
// its view of the result claiming the vector's own cells, and the cast
// after the call gives what @made now returns, claiming nothing. So
// everything @g makes of it claims nothing either: the call to @count,
// whose parameter claims the vector's cells, takes a copy of @count keyed
// to the hold it is passed; the string read from its head is read as
// before; the vector of four @g builds onto it claimed its own family's
// cells unshared, the three it is built on among them, so it claims
// nothing; and where it joins @g's own tail call, whose result still
// claims its cells, that result is shared down, which keeps the tail call.
// The result @g gives takes the hold its return now gives, and every call
// of @g with it. The module verifies as written and after every pass to
// the graded stage, where every tail fact is checked against where its
// call stands. @made and @count each read the length of their vector's
// head, so neither leaves its vector unread. Each function recurses, so
// each stays a function wherever another is inlined into it, and @main
// calls each where no tail is lost, so each returns to more than one place
// and none becomes a join point of its one tail caller.
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
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
!Claimed = !idr.graded<many, counted unique self, !idr.data<#Vect[v0]>>
!Claimed3 = !idr.graded<many, counted unique self, !idr.data<#Vect[3]>>
!Claimed4 = !idr.graded<many, counted unique self, !idr.data<#Vect[4]>>
idr.program @regrading root(@main) stage(first) {
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
    %n = idr.call @count(%a, %k) <{tail_kind = nontail}> : (!Claimed3, i64) -> i64
    %b = idr.call @g(%v3, %xs, %k) <{tail_kind = nontail}> : (!V3, !Unknown, i64) -> !Claimed4
    %c = idr.call @g(%v3, %xs, %n) <{tail_kind = nontail}> : (!V3, !Unknown, i64) -> !Claimed4
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
  idr.func @g(%ys: !V3, %xs: !Unknown, %k: i64) -> !Claimed4 {
    %r = idr.lit.match %k : i64 -> (!Claimed4) {
    case 0(%key0: i64) {
      %v = idr.call @made(%ys, %xs, %k) <{index_args = #idr.index_args<[3]>, tail_kind = nontail}> : (!V3, !Unknown, i64) -> !Claimed3
      %n = idr.call @count(%v, %k) <{tail_kind = nontail}> : (!Claimed3, i64) -> i64
      %h = idr.data.field %v[0] : !Claimed3 -> !idr.str
      %w = idr.data.con(%h : !idr.str, %v : !Claimed3) : !Claimed4
      idr.yield %w : !Claimed4
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.call @g(%ys, %xs, %j) <{tail_kind = tail}> : (!V3, !Unknown, i64) -> !Claimed4
      idr.yield %again : !Claimed4
    }
    }
    idr.return %r : !Claimed4
  } loc("g")
  idr.func @count(%v: !Claimed3, %k: i64) -> i64 {
    %r = idr.lit.match %k : i64 -> (i64) {
    case 0(%key: i64) {
      %h = idr.data.field %v[0] : !Claimed3 -> !idr.str
      %l = idr.str.length %h : (!idr.str) -> i64
      idr.yield %l : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %s = idr.call @count(%v, %j) <{tail_kind = tail}> : (!Claimed3, i64) -> i64
      idr.yield %s : i64
    }
    }
    idr.return %r : i64
  } loc("count")
}
