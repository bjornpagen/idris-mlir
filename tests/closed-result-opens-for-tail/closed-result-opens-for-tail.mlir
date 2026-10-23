// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=tail-calls=@three:@sized,results-as-given=@three:@sized,results-as-given=@three:@three})' -verify-diagnostics -o /dev/null
// A function declared at a closed length keeps its tail call to a callee
// whose length the index language cannot express, by returning its vector
// laid out as at an unknown length. @unknown gives a vector at such a
// length, as Emit writes `Vect (length xs)`: `_`. @sized gives it at the
// length its caller names, so the vector its tail gives is in a cell
// whatever that length is, and no copy of @sized at a known length could
// give it in place without a re-pack after that tail call. @three is
// declared at length 3, three words in place, and tail-calls @sized at 3.
// Its result cannot agree with that tail, so it is laid out as at an
// unknown length: the tail call to @sized is a tail call, and gives its
// result as @sized returns it with no re-pack after it, which the verifier
// holds from the graded stage on. @three also calls itself where no tail
// is lost and hands the vector to @use, which reads it at length 3: that
// call converts the vector after it, the re-pack the error below names.
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
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
idr.program @lengths root(@main) stage(first) {
  idr.func @main() {
    %seed = idr.data.con() : !UnknownNil
    %nil = idr.data.reindex %seed : !UnknownNil to !Unknown
    %k = arith.constant 2 : i64
    %xs = idr.call @unknown(%nil, %k) <{tail_kind = nontail}> : (!Unknown, i64) -> !Unknown
    %two = idr.call @sized(%xs, %k) <{index_args = #idr.index_args<[2]>, tail_kind = nontail}> : (!Unknown, i64) -> !V2
    %v = idr.call @three(%xs, %k) <{tail_kind = nontail}> : (!Unknown, i64) -> !V3
    %h = idr.call @use(%v, %k) <{tail_kind = nontail}> : (!V3, i64) -> i64
    idr.return
  }
  idr.func @unknown(%xs: !Unknown, %k: i64) -> !Unknown {
    %r = idr.lit.match %k : i64 -> (!Unknown) {
    case 0(%key0: i64) {
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
  idr.func <{binders = #idr.index_binders<[nat]>}> @sized(%xs: !Unknown, %k: i64) -> !Vn {
    %r = idr.lit.match %k : i64 -> (!Vn) {
    case 0(%key1: i64) {
      %v = idr.call @unknown(%xs, %k) <{tail_kind = tail}> : (!Unknown, i64) -> !Unknown
      %c = idr.data.reindex %v : !Unknown to !Vn
      idr.yield %c : !Vn
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %v = idr.call @sized(%xs, %j) <{index_args = #idr.index_args<[v0]>, tail_kind = tail}> : (!Unknown, i64) -> !Vn
      idr.yield %v : !Vn
    }
    }
    idr.return %r : !Vn
  } loc("sized")
  idr.func @three(%xs: !Unknown, %k: i64) -> !V3 {
    %r = idr.lit.match %k : i64 -> (!V3) {
    case 0(%key2: i64) {
      %v = idr.call @sized(%xs, %k) <{index_args = #idr.index_args<[3]>, tail_kind = tail}> : (!Unknown, i64) -> !V3
      idr.yield %v : !V3
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      // expected-error @below {{expected results-as-given: }}
      %w = idr.call @three(%xs, %j) <{tail_kind = nontail}> : (!Unknown, i64) -> !V3
      %h = idr.call @use(%w, %j) <{tail_kind = nontail}> : (!V3, i64) -> i64
      idr.yield %w : !V3
    }
    }
    idr.return %r : !V3
  } loc("three")
  idr.func @use(%v: !V3, %k: i64) -> i64 {
    %r = idr.lit.match %k : i64 -> (i64) {
    case 0(%key3: i64) {
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
