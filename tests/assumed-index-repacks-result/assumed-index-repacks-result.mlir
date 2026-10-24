// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=higher to=higher},idr-expect{holds=results-as-given=@kept:@g})' -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=higher to=higher},idr-expect{holds=results-as-given=@repacked:@g})' -verify-diagnostics -o /dev/null
// A value a call gives may enter a region in which an erased equality
// holds, bound there at the type the equality refines it to. @g returns a
// vector of a length its caller gives, laid out as at a length unknown when
// it is compiled, in a cell. @repacked calls @g at its own length and
// assumes that length is four; its region binds the vector at four, laid
// out in place, so the region's entry re-packs the cell the call gave, and
// the call pays a re-pack for its result. @kept assumes the same, and its
// region binds the vector at four marked open, laid out in a cell as @g
// returns it: another type, the same words, so nothing re-packs it.
// The program is at stage higher; the slice at higher runs no pass, so the
// property reads the module as written.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
!V4 = !idr.data<#Vect[4]>
!V4open = !idr.data<#Vect[4] open>
!Vn = !idr.data<#Vect[v0]>
idr.program @entries root(@main) stage(higher) {
  idr.func @main() {
    idr.return
  }
  idr.func <{binders = #idr.index_binders<[nat]>}> @g(%xs: !Vn) -> !Vn {
    idr.return %xs : !Vn
  }
  idr.func <{binders = #idr.index_binders<[nat]>}> @repacked(%xs: !Vn) -> i64 {
    // expected-error @below {{expected results-as-given: }}
    %r = idr.call @g(%xs) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (!Vn) -> !Vn
    %t = idr.index.assume #idr.equation<v0 = 4> (%r : !Vn) -> (i64) {
    ^bb0(%w: !V4):
      %tag = idr.data.tag %w : !V4
      idr.yield %tag : i64
    }
    idr.return %t : i64
  }
  idr.func <{binders = #idr.index_binders<[nat]>}> @kept(%xs: !Vn) -> i64 {
    %r = idr.call @g(%xs) <{index_args = #idr.index_args<[v0]>, tail_kind = nontail}> : (!Vn) -> !Vn
    %t = idr.index.assume #idr.equation<v0 = 4> (%r : !Vn) -> (i64) {
    ^bb0(%w: !V4open):
      %tag = idr.data.tag %w : !V4open
      idr.yield %tag : i64
    }
    idr.return %t : i64
  }
}
