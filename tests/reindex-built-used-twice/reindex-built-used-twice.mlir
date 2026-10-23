// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=owned})' -o /dev/null
// A value born claiming its own cells unshared that counting duplicates is
// shared from then on, so it is given on with the claim forgotten where it
// is made, the grade's way, and the duplicate is taken of that: a dup of a
// value that claims its cells unshared cannot be written. Four words in
// place hold no reference; laid out open, as at a length unknown at
// compile time, the same vector is a cell, so @make's cast builds it,
// counted and claiming its own cells. @make puts the vector in both fields
// of a pair, each field taking a reference of it, so the first takes a
// second reference while the second still needs the vector. The slice
// from the graded stage to the owned stage is verified after every pass,
// so it verifies, with nothing expected, only where the vector is
// duplicated once its claim is forgotten and each of the two references
// is moved on once, into its field.
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
!Open = !idr.data<#Vect[4] open>
#Pair = #idr.family<"Pair" [] {
    @MkPair (!idr.data<#Vect[4] open>, !idr.data<#Vect[4] open>)
  }>
!Pair = !idr.data<#Pair>
idr.program @twice root(@main) stage(graded) {
  idr.func @main() {
    %seven = arith.constant 7 : i64
    %p = idr.call @make(%seven) <{tail_kind = nontail}> : (i64) -> !Pair
    %v = idr.data.field %p[1] : !Pair -> !Open
    %head = idr.data.field %v[0] : !Open -> i64
    %text = idr.str.show_sint %head : (i64) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
  idr.func @make(%x: i64) -> !Pair {
    %nil = idr.data.con() : !V0
    %v1 = idr.data.con(%x : i64, %nil : !V0) : !V1
    %v2 = idr.data.con(%x : i64, %v1 : !V1) : !V2
    %v3 = idr.data.con(%x : i64, %v2 : !V2) : !V3
    %v4 = idr.data.con(%x : i64, %v3 : !V3) : !V4
    %built = idr.data.reindex %v4 : !V4 to !Built
    %p = idr.data.con(%built : !Built, %built : !Built) : !Pair
    idr.return %p : !Pair
  }
}
