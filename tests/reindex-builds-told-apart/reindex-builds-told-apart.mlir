// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=lowered})' -o /dev/null
// Whether a reindex builds a cell is one answer, which the reindex's own
// check, its flow and the lowering's re-pack all read, so a reindex that
// builds and one that builds nothing are told apart alike by each. Two
// strings in place hold references; laid out open, as at a length unknown
// at compile time, the same vector is a cell. @make builds the two strings
// in place and casts them to the open layout, which builds the cell: its
// result is a fresh value, counted, which used many times claims nothing
// before references are counted, as the words it was built from claim
// nothing. @apart casts the open vector back to its two strings in place,
// which takes the cell apart and builds nothing: its result keeps the hold
// its operand has, and its flow gives no fresh value. So the module
// verifies only where both casts are told apart rightly. @words builds four words in place, which
// hold no reference and so are only read where they are, and casts them to
// the open layout, which builds a cell: the lowering's re-pack asks the
// same answer before it reads them into it. The module verifies as written
// and after every pass from the graded stage through the lowering. @main
// prints the head of the strings @apart gives and of the words @words
// gives, so every cast's result is read.
#VS = #idr.family<"VS" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (!idr.str, !idr.self[v0])
  }>
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
!S0 = !idr.data<#VS[0]>
!S1 = !idr.data<#VS[1]>
!S2 = !idr.data<#VS[2]>
!S2Open = !idr.data<#VS[2] open>
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
!V4 = !idr.data<#Vect[4]>
!V4Open = !idr.data<#Vect[4] open>
idr.program @repacks root(@main) stage(graded) {
  idr.func @main() {
    %seven = arith.constant 7 : i64
    %open = idr.call @make(%seven) : (i64) -> !S2Open
    %strings = idr.call @apart(%open) : (!S2Open) -> !S2
    %text = idr.data.field %strings[0] : !S2 -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    %words = idr.call @words(%seven) : (i64) -> !V4Open
    %head = idr.data.field %words[0] : !V4Open -> i64
    %shown = idr.str.show_sint %head : (i64) -> !idr.str
    idr.io.put_str %shown : (!idr.str) -> ()
    idr.return
  }
  idr.func @make(%x: i64) -> !S2Open {
    %s = idr.str.show_sint %x : (i64) -> !idr.str
    %nil = idr.data.con() : !S0
    %v1 = idr.data.con(%s : !idr.str, %nil : !S0) : !S1
    %v2 = idr.data.con(%s : !idr.str, %v1 : !S1) : !S2
    %built = idr.data.reindex %v2 : !S2 to !S2Open
    idr.return %built : !S2Open
  }
  idr.func @apart(%v: !S2Open) -> !S2 {
    %strings = idr.data.reindex %v : !S2Open to !S2
    idr.return %strings : !S2
  }
  idr.func @words(%x: i64) -> !V4Open {
    %nil = idr.data.con() : !V0
    %v1 = idr.data.con(%x : i64, %nil : !V0) : !V1
    %v2 = idr.data.con(%x : i64, %v1 : !V1) : !V2
    %v3 = idr.data.con(%x : i64, %v2 : !V2) : !V3
    %v4 = idr.data.con(%x : i64, %v3 : !V3) : !V4
    %built = idr.data.reindex %v4 : !V4 to !V4Open
    idr.return %built : !V4Open
  }
}
