// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=graded to=lowered})' -o /dev/null
// A closed value held in place whose constructor binds a binder its
// indices leave open lays each field out at the binders they solve: a
// field that names only solved binders is in place at closed terms, one
// that names the open binder is at the constructor's own. Every reader of
// the value's fields reads them so: building it, reading a field, and
// re-packing it into another layout. A box of 3 holds a vector of 3 words,
// whose length its index fixes, and a vector whose length its constructor
// binds and no index fixes, so the first is three words in place and the
// second a cell. @make builds a box of a vector of 3 and one of 2, which
// goes into its cell. @main reads the second vector's head, then has @open
// cast the box to the open layout, at which the first field is a cell
// too, so the cast builds one, a fresh value counted and claiming its own
// cells, which a share then forgets; @main reads the first vector's head
// out of the opened box. Each field's values fill the slots the box's type
// laid out, so the module verifies after every pass from the graded stage
// through the lowering only where every reader takes each field at the
// type its slots hold.
#Vect = #idr.family<"Vect" [nat] {
    @Nil where 0 ()
    @Cons <nat> where v0 + 1 (i64, !idr.self[v0])
  }>
#Box = #idr.family<"Box" [nat] {
    @MkBox <nat, nat> where v0 (!idr.data<#Vect[v0]>, !idr.data<#Vect[v1]>)
  }>
!V0 = !idr.data<#Vect[0]>
!V1 = !idr.data<#Vect[1]>
!V2 = !idr.data<#Vect[2]>
!V3 = !idr.data<#Vect[3]>
!Box = !idr.data<#Box[3] @MkBox<3, 2>>
!Opened = !idr.data<#Box[3] open @MkBox<3, 2>>
!OpenedBuilt = !idr.graded<many, counted unique self, !idr.data<#Box[3] open @MkBox<3, 2>>>
idr.program @boxes root(@main) stage(graded) {
  idr.func @main() {
    %seven = arith.constant 7 : i64
    %box = idr.call @make(%seven) <{tail_kind = nontail}> : (i64) -> !Box
    %ys = idr.data.field %box[1] : !Box -> !V2
    %y = idr.data.field %ys[0] : !V2 -> i64
    %shown = idr.str.show_sint %y : (i64) -> !idr.str
    idr.io.put_str %shown : (!idr.str) -> ()
    %opened = idr.call @open(%box) <{tail_kind = nontail}> : (!Box) -> !Opened
    %xs = idr.data.field %opened[0] : !Opened -> !V3
    %x = idr.data.field %xs[0] : !V3 -> i64
    %again = idr.str.show_sint %x : (i64) -> !idr.str
    idr.io.put_str %again : (!idr.str) -> ()
    idr.return
  }
  idr.func @make(%x: i64) -> !Box {
    %nil = idr.data.con() : !V0
    %v1 = idr.data.con(%x : i64, %nil : !V0) : !V1
    %v2 = idr.data.con(%x : i64, %v1 : !V1) : !V2
    %v3 = idr.data.con(%x : i64, %v2 : !V2) : !V3
    %box = idr.data.con(%v3 : !V3, %v2 : !V2) : !Box
    idr.return %box : !Box
  }
  idr.func @open(%box: !Box) -> !Opened {
    %built = idr.data.reindex %box : !Box to !OpenedBuilt
    %shared = idr.count.share %built : !OpenedBuilt
    idr.return %shared : !Opened
  }
}
