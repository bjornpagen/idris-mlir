// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=tail-calls=@three:@sized,results-as-given=@three:@sized,results-as-given=@sized:@unknown})' -o /dev/null
// A copy that closes a length keeps a tail whose length the index language
// cannot express, and a caller at that length keeps its tail call to the
// copy. @unknown gives a vector at such a length, as Emit writes `Vect
// (length xs)`: `_`. @sized takes a vector at the length it names, reads
// its head, and gives the vector its tail call to @unknown gives, cast to
// that length: a cast from `_` to `v0`. @three is declared at length 3 and
// tail-calls @sized at 3, passing three words in place, so @sized's copy at
// 3 lays its parameter out in place, and in it the cast is from `_` to 3,
// admitted as the cast to `v0` was: the module verifies after every pass to
// the graded stage. The copy's result cannot be laid out in place after a
// tail that gives `_`, which no substitution closes, so @sized returns its
// vector laid out as at an unknown length, and so does every copy of it:
// the copy's tail call to @unknown gives its result as @unknown returns
// it, with no re-pack after it. @three's own result cannot agree with its
// tail call to the copy, so it is laid out open too: that call is a tail
// call and gives its result as the copy returns it. @three also builds
// three words in place at another tail: laid out open they are a fresh
// cell, claiming its own cells, which shares down to the hold the tail call
// gives, so both tails give one open type. @three calls itself where no
// tail is lost and hands the vector to @use, which reads it at length 3.
// @main calls @unknown, @sized and @three where no tail is lost, so each
// returns to more than one place and stays a function, never a join point
// of its one tail caller; and each recurses, so each stays a function
// wherever another is inlined into it.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
!Unknown = !idr.data<#Vect[_]>
!UnknownNil = !idr.data<#Vect[_] @Nil>
!Vn = !idr.data<#Vect[v0]>
!VnNil = !idr.data<#Vect[v0] @Nil>
!VnCons = !idr.data<#Vect[v0] @Cons<v1>>
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
idr.program @lengths root(@main) stage(first) {
  idr.func @main() {
    %x = arith.constant 7 : i64
    %nil = idr.data.con() : !V0
    %v1 = idr.data.con(%x : i64, %nil : !V0) : !V1
    %v2 = idr.data.con(%x : i64, %v1 : !V1) : !V2
    %v3 = idr.data.con(%x : i64, %v2 : !V2) : !V3
    %seed = idr.data.con() : !UnknownNil
    %xs = idr.data.reindex %seed : !UnknownNil to !Unknown
    %k = arith.constant 2 : i64
    %u = idr.call @unknown(%xs, %k) <{tail_kind = nontail}> : (!Unknown, i64) -> !Unknown
    %s = idr.call @sized(%v3, %xs, %k) <{index_args = #idr.index_args<[3]>, tail_kind = nontail}> : (!V3, !Unknown, i64) -> !V3
    %a = idr.call @use(%s, %k) <{tail_kind = nontail}> : (!V3, i64) -> i64
    %t = idr.call @three(%v3, %xs, %k) <{tail_kind = nontail}> : (!V3, !Unknown, i64) -> !V3
    %b = idr.call @use(%t, %k) <{tail_kind = nontail}> : (!V3, i64) -> i64
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
  idr.func <{binders = #idr.index_binders<[nat]>}> @sized(%ys: !Vn, %xs: !Unknown, %k: i64) -> !Vn {
    %r = idr.lit.match %k : i64 -> (!Vn) {
    case 0(%key: i64) {
      %head = idr.data.match %ys : !Vn -> (i64) {
      case @Nil(%n: !VnNil) {
        idr.yield %key : i64
      }
      case @Cons(%c: !VnCons) {
        %h = idr.data.field %c[0] : !VnCons -> i64
        idr.yield %h : i64
      }
      }
      %v = idr.call @unknown(%xs, %head) <{tail_kind = tail}> : (!Unknown, i64) -> !Unknown
      %c = idr.data.reindex %v : !Unknown to !Vn
      idr.yield %c : !Vn
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %v = idr.call @sized(%ys, %xs, %j) <{index_args = #idr.index_args<[v0]>, tail_kind = tail}> : (!Vn, !Unknown, i64) -> !Vn
      idr.yield %v : !Vn
    }
    }
    idr.return %r : !Vn
  } loc("sized")
  idr.func @three(%ys: !V3, %xs: !Unknown, %k: i64) -> !V3 {
    %r = idr.lit.match %k : i64 -> (!V3) {
    case 0(%key0: i64) {
      %v = idr.call @sized(%ys, %xs, %k) <{index_args = #idr.index_args<[3]>, tail_kind = tail}> : (!V3, !Unknown, i64) -> !V3
      idr.yield %v : !V3
    }
    case 1(%key1: i64) {
      %nil = idr.data.con() : !V0
      %w1 = idr.data.con(%key1 : i64, %nil : !V0) : !V1
      %w2 = idr.data.con(%key1 : i64, %w1 : !V1) : !V2
      %w3 = idr.data.con(%key1 : i64, %w2 : !V2) : !V3
      idr.yield %w3 : !V3
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %w = idr.call @three(%ys, %xs, %j) <{tail_kind = nontail}> : (!V3, !Unknown, i64) -> !V3
      %h = idr.call @use(%w, %j) <{tail_kind = nontail}> : (!V3, i64) -> i64
      idr.yield %w : !V3
    }
    }
    idr.return %r : !V3
  } loc("three")
  idr.func @use(%v: !V3, %k: i64) -> i64 {
    %r = idr.lit.match %k : i64 -> (i64) {
    case 0(%key: i64) {
      %h = idr.data.field %v[0] : !V3 -> i64
      idr.yield %h : i64
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %s = idr.call @use(%v, %j) <{tail_kind = tail}> : (!V3, i64) -> i64
      idr.yield %s : i64
    }
    }
    idr.return %r : i64
  } loc("use")
}
