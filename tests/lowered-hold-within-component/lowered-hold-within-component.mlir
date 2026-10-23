// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded})' -o /dev/null
// A member of a recursion that another member passes a weaker hold than
// its parameter claims takes that hold as its parameter's, since no copy of
// a member is keyed while its component is not final. Three strings in
// place hold references; laid out at a length unknown at compile time, the
// same vector is a cell. @made is declared to give a vector at its own
// length, counted and claiming its own cells, but where it assumes the
// length is 3 it re-packs what @unknown gives (a vector at a length the
// index language cannot express, `_`, claiming nothing) into three strings
// in place and casts those to its own length: that tail cannot agree with a
// result laid out at the function's own length, so the result is laid out
// open, at the hold that tail gives, which claims nothing. @first and
// @second call each other, one component. @first calls @made at length 3,
// and the cast after the call gives what @made now returns, claiming
// nothing, which @first passes to @second, whose parameter claims the
// vector's own cells. So when the component is taken up, @second's
// parameter takes the weaker hold, the read of its head is inferred again
// from it, its own tail call passes the parameter on at that hold, and
// every call of it passes its operand at that hold: @first's as it is, and
// @main's, which gives what @made returns too. The module verifies as
// written and after every pass to the graded stage, where every call's
// types are its callee's, grade included. @second reads the length of its
// vector's head, and @made reads its own vector's, so neither leaves its
// vector unread. Each function recurses, so each stays a function wherever
// another is inlined into it, and @main calls each where no tail is lost,
// so each returns to more than one place and none becomes a join point of
// its one tail caller.
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
idr.program @component root(@main) stage(first) {
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
    %m = idr.call @first(%v3, %xs, %k) <{tail_kind = nontail}> : (!V3, !Unknown, i64) -> i64
    %n = idr.call @second(%a, %v3, %xs, %k) <{tail_kind = nontail}> : (!Claimed3, !V3, !Unknown, i64) -> i64
    %o = idr.call @first(%v3, %xs, %n) <{tail_kind = nontail}> : (!V3, !Unknown, i64) -> i64
    %p = idr.call @second(%a, %v3, %xs, %m) <{tail_kind = nontail}> : (!Claimed3, !V3, !Unknown, i64) -> i64
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
  idr.func @first(%ys: !V3, %xs: !Unknown, %k: i64) -> i64 {
    %r = idr.lit.match %k : i64 -> (i64) {
    case 0(%key0: i64) {
      %v = idr.call @made(%ys, %xs, %k) <{index_args = #idr.index_args<[3]>, tail_kind = nontail}> : (!V3, !Unknown, i64) -> !Claimed3
      %n = idr.call @second(%v, %ys, %xs, %k) <{tail_kind = nontail}> : (!Claimed3, !V3, !Unknown, i64) -> i64
      %one = arith.constant 1 : i64
      %m = arith.addi %n, %one : i64
      idr.yield %m : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.call @first(%ys, %xs, %j) <{tail_kind = tail}> : (!V3, !Unknown, i64) -> i64
      idr.yield %again : i64
    }
    }
    idr.return %r : i64
  } loc("first")
  idr.func @second(%v: !Claimed3, %ys: !V3, %xs: !Unknown, %k: i64) -> i64 {
    %r = idr.lit.match %k : i64 -> (i64) {
    case 0(%key0: i64) {
      %h = idr.data.field %v[0] : !Claimed3 -> !idr.str
      %l = idr.str.length %h : (!idr.str) -> i64
      idr.yield %l : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %m = idr.call @first(%ys, %xs, %j) <{tail_kind = nontail}> : (!V3, !Unknown, i64) -> i64
      %again = idr.call @second(%v, %ys, %xs, %m) <{tail_kind = tail}> : (!Claimed3, !V3, !Unknown, i64) -> i64
      idr.yield %again : i64
    }
    }
    idr.return %r : i64
  } loc("second")
}
