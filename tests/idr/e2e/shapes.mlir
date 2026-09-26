// RUN: idris-mlir-cc %s -o %t.o && cc %t.o -o %t && not %t; test $? -eq 42 || (%t; test $? -eq 42)
module attributes {idr.version = 0 : i64, idr.entry = @Prog.main, idr.entry_kind = "int"} {
  idr.data @Prog.Shape attributes {idr.name = "Prog.Shape"} {
    idr.ctor @Circle tag 0 fields [i64] quantities ["w"] {idr.name = "Prog.Circle"}
    idr.ctor @Rect tag 1 fields [i64, i64] quantities ["w", "w"] {idr.name = "Prog.Rect"}
  }
  func.func private @Prog.area(%s: !idr.data<@Prog.Shape> {idr.quantity = "w"}) -> i64 attributes {idr.name = "Prog.area"} {
    %t = idr.tag %s : !idr.data<@Prog.Shape>
    %r = scf.index_switch %t -> i64
    case 0 {
      %x = idr.field %s[@Circle, 0] : !idr.data<@Prog.Shape> -> i64
      %c3 = arith.constant 3 : i64
      %xx = arith.muli %x, %x : i64
      %a = arith.muli %c3, %xx : i64
      scf.yield %a : i64
    }
    default {
      %w = idr.field %s[@Rect, 0] : !idr.data<@Prog.Shape> -> i64
      %h = idr.field %s[@Rect, 1] : !idr.data<@Prog.Shape> -> i64
      %a = arith.muli %w, %h : i64
      scf.yield %a : i64
    }
    return %r : i64
  }
  func.func private @Prog.keep(%w: !idr.erased {idr.quantity = "0"}, %v: i64 {idr.quantity = "w"}) -> i64 attributes {idr.name = "Prog.keep"} {
    return %v : i64
  }
  func.func private @Prog.main() -> i64 attributes {idr.name = "Prog.main"} {
    %e = idr.erased : !idr.erased
    %c6 = arith.constant 6 : i64
    %c7 = arith.constant 7 : i64
    %s = idr.con @Prog.Shape::@Rect(%c6, %c7) : (i64, i64) -> !idr.data<@Prog.Shape>
    %a = func.call @Prog.area(%s) : (!idr.data<@Prog.Shape>) -> i64
    %r = func.call @Prog.keep(%e, %a) : (!idr.erased, i64) -> i64
    return %r : i64
  }
}
