// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=owned})' -o /dev/null
// An update's region may not read or write the contents or a state above
// them, since the element's place is empty while it runs; counting's own
// work in the region passes: the cell it fills, beneath the contents and
// reached by no value but its own, and what it drops or frees on the heap,
// which gives memory back and sees no place.
// @main reads two lines, so neither string is a constant, holds the list
// of them in mutable memory, and updates it to the list of its head alone:
// the region reads the element's head, leaves its tail unread, and builds
// a cell of the same constructor from the head. Counting takes the element
// apart where its head is read, drops what it does not move on, and fills
// a cell, the element's own where it was unshared, with the head and the
// empty tail, all inside the region. Then @main reads the list back and
// writes its head. The module starts first-order and is verified after
// every pass to the owned stage, so it verifies, with nothing expected,
// only where the region's rule is read off the tree: a cell filled and
// what is dropped or freed on the heap pass, and no read or write of the
// contents is among them.
#List = #idr.family<"List" [] {
    @Nil ()
    @Cons (!idr.str, !idr.self)
  }>
!Nil = !idr.data<#List @Nil>
!Cons = !idr.data<#List @Cons>
!Ref = memref<!Cons, #idr.mutable>
idr.program @updates root(@main) stage(first) {
  idr.func @main() {
    %first = idr.io.get_line : () -> !idr.str
    %second = idr.io.get_line : () -> !idr.str
    %nil = idr.data.con() : !Nil
    %tail = idr.data.con(%second : !idr.str, %nil : !Nil) : !Cons
    %list = idr.data.con(%first : !idr.str, %tail : !Cons) : !Cons
    %ref = idr.array.new [], %list : !Cons -> !Ref
    idr.array.update %ref[] {
    ^bb0(%held: !Cons):
      %head = idr.data.field %held[0] : !Cons -> !idr.str
      %end = idr.data.con() : !Nil
      %rebuilt = idr.data.con(%head : !idr.str, %end : !Nil) : !Cons
      idr.array.update_yield %rebuilt : !Cons
    } : !Ref
    %now = idr.array.get %ref[] : !Ref -> !Cons
    %text = idr.data.field %now[0] : !Cons -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
}
