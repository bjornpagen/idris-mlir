// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=higher to=higher},idr-expect{holds=tail-calls=@jumps:@next,results-as-given=@given:@g})' -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=higher to=higher},idr-expect{holds=tail-calls=@adds:@next,tail-calls=@use:@next,results-as-given=@unspecialized:@g,results-as-given=@repacks:@g})' -verify-diagnostics -o /dev/null
// What follows a call. @jumps calls @next as its last act, a tail call;
// @adds adds to what @next gives, so its call is none, and @use calls no
// @next at all. @g returns a vector of a length its caller gives, laid out
// as at a length unknown when it is compiled, in a cell; @g_4 is its copy
// at four, which returns the vector in place. @given takes @g_4's result
// as @g_4 lays it out. @unspecialized calls @g itself at four: the call's
// type has the result in place, but @g returns a cell. @repacks calls @g
// at its own length, where that length is known to be four, and re-packs
// the cell in place before it hands it on.
// The program is at stage higher, where a call's tail fact is a promise.
// The slice at higher runs no pass, so each property reads the module as
// written.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
!V4 = !idr.data<#Vect[4]>
!Vn = !idr.data<#Vect[v0]>
idr.program @calls root(@main) stage(higher) {
  idr.func @main() {
    idr.return
  }
  idr.func @next(%n: i64) -> i64 {
    %one = arith.constant 1 : i64
    %m = arith.addi %n, %one : i64
    idr.return %m : i64
  }
  idr.func @jumps(%n: i64) -> i64 {
    %r = idr.call @next(%n) <{tail_kind = tail}> : (i64) -> i64
    idr.return %r : i64
  }
  idr.func @adds(%n: i64) -> i64 {
    // expected-error @below {{expected tail-calls: }}
    %r = idr.call @next(%n) <{tail_kind = nontail}> : (i64) -> i64
    %one = arith.constant 1 : i64
    %s = arith.addi %r, %one : i64
    idr.return %s : i64
  }
  // expected-error @below {{expected tail-calls: }}
  idr.func @use(%xs: !V4) -> i64 {
    %zero = arith.constant 0 : i64
    idr.return %zero : i64
  }
  idr.func <{binders = #idr.index_binders<[nat]>}> @g(%xs: !Vn) -> !Vn {
    idr.return %xs : !Vn
  }
  idr.func @g_4(%xs: !V4) -> !V4 {
    idr.return %xs : !V4
  } loc("g")
  idr.func @given(%xs: !V4) -> i64 {
    %r = idr.call @g_4(%xs) <{tail_kind = nontail}> : (!V4) -> !V4
    %t = idr.call @use(%r) <{tail_kind = tail}> : (!V4) -> i64
    idr.return %t : i64
  }
  idr.func @unspecialized(%xs: !V4) -> i64 {
    // expected-error @below {{expected results-as-given: }}
    %r = idr.call @g(%xs) <{index_args = #idr.index_args<[4]>, tail_kind = nontail}> : (!V4) -> !V4
    %t = idr.call @use(%r) <{tail_kind = tail}> : (!V4) -> i64
    idr.return %t : i64
  }
  idr.func <{binders = #idr.index_binders<[nat]>}> @repacks(%xs: !Vn) -> i64 {
    %t = idr.index.assume #idr.equation<v0 = 4> () -> (i64) {
      // expected-error @below {{expected results-as-given: }}
      %r = idr.call @g(%xs) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (!Vn) -> !Vn
      %p = idr.data.reindex %r : !Vn to !V4
      %u = idr.call @use(%p) <{tail_kind = tail}> : (!V4) -> i64
      idr.yield %u : i64
    }
    idr.return %t : i64
  }
}
