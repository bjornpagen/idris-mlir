// RUN: idris-mlir-opt %s --idr-rc -o %t.owned.mlir
// RUN: %differential %s %t.owned.mlir
// A sum that holds a string in every case, matched twice in a row.
// The first match rebuilds it under the next constructor; the second
// match's scrutinee is that owned sum, which no case uses (the fields
// come bound), so counting takes it apart at each case's entry with
// an unpack written there. Where the sum's reference dies on each
// case is then read off the numbered places of ops counting itself
// inserted at the starts of sibling case blocks: each belongs to its
// own case, and no case's numbering may reach into another's. The
// root builds @A of the input byte shown, swaps it to @B and prints
// the field back, so byte 7 prints "7".
// STDIN: \0007
// A scrutinee taken apart at each case's entry dies in its own case.
!S = !idr.data<"S">
#types = #idr.types<
  "S" = plain [@A(!idr.str), @B(!idr.str), @C(!idr.str)]
>
idr.program @"fixture" root(@root) stage(first) types #types {
  idr.func @swap(%s: !S) -> !S attributes {total} {
    %r = idr.match %s : !S -> (!S) {
    case @A(%a: !idr.str) {
      %c = idr.con !S @B(%a : !idr.str)
      idr.yield %c : !S
    }
    case @B(%b: !idr.str) {
      %c = idr.con !S @C(%b : !idr.str)
      idr.yield %c : !S
    }
    case @C(%c0: !idr.str) {
      %c = idr.con !S @A(%c0 : !idr.str)
      idr.yield %c : !S
    }
    }
    return %r : !S
  }
  idr.func @pick(%s: !S) -> !idr.str attributes {total} {
    %t = idr.call @swap(%s) : (!S) -> !S
    %r = idr.match %t : !S -> (!idr.str) {
    case @A(%a: !idr.str) {
      idr.yield %a : !idr.str
    }
    case @B(%b: !idr.str) {
      idr.yield %b : !idr.str
    }
    case @C(%c0: !idr.str) {
      idr.yield %c0 : !idr.str
    }
    }
    return %r : !idr.str
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %s0 = idr.str.show_sint %x : i64
    %v = idr.con !S @A(%s0 : !idr.str)
    %r = idr.call @pick(%v) : (!S) -> !idr.str
    %w1 = idr.io.put_str %r, %w0
    return %w1 : !idr.world
  }
}
