// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=owned})' -o /dev/null
// An element's update moves the element out of its place into its region
// with the reference the place held, the place empty until the region's end
// moves the rebuilt one back in, as the take a split update becomes does:
// the element is a value of the region's own, never a view of the array.
// @main reads two lines, so neither string is a constant, holds their pair
// in mutable memory, and updates it to the pair swapped: the region takes
// the element apart, each string moving out of it, and builds the swapped
// pair of them, which moves back into the place. Then it reads the pair
// back and writes its first string. The pair is held in place, so taking it
// apart and building it touch no memory written in place, which an update's
// region may not. The module starts first-order and is verified after every
// pass to the owned stage, so it verifies, with nothing expected, only
// where counting and the linearity rule read the element alike: a value
// holding its own reference, taken apart once, each string moved on once.
#Pair = #idr.family<"Pair" [] {
    @MkPair (!idr.str, !idr.str)
  }>
!Pair = !idr.data<#Pair>
!Ref = memref<!Pair, #idr.mutable>
idr.program @updates root(@main) stage(first) {
  idr.func @main() {
    %first = idr.io.get_line : () -> !idr.str
    %second = idr.io.get_line : () -> !idr.str
    %pair = idr.data.con(%first : !idr.str, %second : !idr.str) : !Pair
    %ref = idr.array.new [], %pair : !Pair -> !Ref
    idr.array.update %ref[] {
    ^bb0(%held: !Pair):
      %a = idr.data.field %held[0] : !Pair -> !idr.str
      %b = idr.data.field %held[1] : !Pair -> !idr.str
      %swapped = idr.data.con(%b : !idr.str, %a : !idr.str) : !Pair
      idr.array.update_yield %swapped : !Pair
    } : !Ref
    %now = idr.array.get %ref[] : !Ref -> !Pair
    %text = idr.data.field %now[0] : !Pair -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
}
