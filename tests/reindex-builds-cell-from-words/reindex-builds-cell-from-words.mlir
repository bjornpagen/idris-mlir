// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded})' -o /dev/null
// A reindex that builds a cell gives a fresh value, counted and claiming
// its own cells where its uses let it, whatever its operand holds, and
// keeps the operand's uses. Four words in place hold no reference, so
// their vector has no hold; laid out open, as at a length unknown at
// compile time, the same vector is a cell. @make builds the four words in
// place, used once, and casts them to the open layout, which builds the
// cell: the cast relates a vector with no hold to one used once, counted
// and claiming its own cells, the grade the build gives, and the
// refinements around it make the two the same vector, its length 4 kept.
// The module verifies as written and after every pass to the graded
// stage. @main writes the vector's head, so the cast's result is read.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
!V4 = !idr.graded<once, !idr.data<#Vect[4]>>
!Open = !idr.graded<once, counted unique self, !idr.data<#Vect[4] open>>
idr.program @words root(@main) stage(first) {
  idr.func @main() {
    %seven = arith.constant 7 : i64
    %v = idr.call @make(%seven) <{tail_kind = nontail}> : (i64) -> !Open
    %head = idr.data.field %v[0] : !Open -> i64
    %text = idr.str.show_sint %head : (i64) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
  idr.func @make(%x: i64) -> !Open {
    %nil = idr.data.con() : !V0
    %v1 = idr.data.con(%x : i64, %nil : !V0) : !V1
    %v2 = idr.data.con(%x : i64, %v1 : !V1) : !V2
    %v3 = idr.data.con(%x : i64, %v2 : !V2) : !V3
    %v4 = idr.data.con(%x : i64, %v3 : !V3) : !V4
    %open = idr.data.reindex %v4 : !V4 to !Open
    idr.return %open : !Open
  }
}
