// RUN: idris-mlir-opt %s -o /dev/null
// A cast from an index the language cannot write is admitted to whatever
// term its result names, so a function and its copy at a closed index
// verify alike. @unknown gives a vector at a length the index language
// cannot express, as Emit writes `Vect (length xs)`: `_`. @sized gives, at
// the length it names, what its tail call to @unknown gives, cast from `_`
// to `v0`. @sized_3 is its copy at 3, its binder replaced by 3 and its
// result laid out as at an unknown length, as every copy of it is, so its
// call stays a tail: the same cast, now from `_` to 3, whose operand may
// hold any constructor by its own type and whose result only `@Cons`. The
// module verifies as written, both casts admitted by the cast's own check
// and by the scope rule.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
!Unknown = !idr.data<#Vect[_]>
!UnknownNil = !idr.data<#Vect[_] @Nil>
!Vn = !idr.data<#Vect[v0]>
!V3 = !idr.data<#Vect[3]>
!V3Open = !idr.data<#Vect[3] open>
idr.program @lengths root(@main) stage(first) {
  idr.func @main() {
    %seed = idr.data.con() : !UnknownNil
    %xs = idr.data.reindex %seed : !UnknownNil to !Unknown
    %generic = idr.call @sized(%xs) <{index_args = #idr.index_args<[3]>, tail_kind = nontail}> : (!Unknown) -> !V3
    %copy = idr.call @sized_3(%xs) <{tail_kind = nontail}> : (!Unknown) -> !V3Open
    idr.return
  }
  idr.func @unknown(%xs: !Unknown) -> !Unknown {
    idr.return %xs : !Unknown
  }
  idr.func <{binders = #idr.index_binders<[nat]>}> @sized(%xs: !Unknown) -> !Vn {
    %v = idr.call @unknown(%xs) <{tail_kind = tail}> : (!Unknown) -> !Unknown
    %c = idr.data.reindex %v : !Unknown to !Vn
    idr.return %c : !Vn
  }
  idr.func @sized_3(%xs: !Unknown) -> !V3Open {
    %v = idr.call @unknown(%xs) <{tail_kind = tail}> : (!Unknown) -> !Unknown
    %c = idr.data.reindex %v : !Unknown to !V3Open
    idr.return %c : !V3Open
  }
}
