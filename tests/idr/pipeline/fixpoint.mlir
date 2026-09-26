// RUN: idris-mlir-opt %s --idr-check-input --idr-entry --inline --idr-tail-loops --sccp --canonicalize --cse --symbol-dce > %t1.mlir
// RUN: idris-mlir-opt %t1.mlir --inline --idr-tail-loops --sccp --canonicalize --cse --symbol-dce > %t2.mlir
// RUN: diff %t1.mlir %t2.mlir
// rule: OPT-IDEM-1, OPT-PIPE-1, OPT-PIPE-3, IDR-IF-1
module attributes {idr.version = 0 : i64, idr.entry = @Prog.main, idr.entry_kind = "int"} {
  idr.data @S attributes {idr.name = "S"} {
    idr.ctor @A tag 0 fields [i64] quantities ["w"] {idr.name = "A"}
    idr.ctor @B tag 1 fields [i64, i64] quantities ["w", "w"] {idr.name = "B"}
  }
  func.func private @area(%s: !idr.data<@S> {idr.quantity = "w"}) -> i64 attributes {idr.name = "area"} {
    %t = idr.tag %s : !idr.data<@S>
    %r = scf.index_switch %t -> i64
    case 0 {
      %x = idr.field %s[@A, 0] : !idr.data<@S> -> i64
      scf.yield %x : i64
    }
    default {
      %w = idr.field %s[@B, 0] : !idr.data<@S> -> i64
      %h = idr.field %s[@B, 1] : !idr.data<@S> -> i64
      %a = arith.muli %w, %h : i64
      scf.yield %a : i64
    }
    return %r : i64
  }
  func.func private @Prog.main() -> i64 attributes {idr.name = "main"} {
    %c6 = arith.constant 6 : i64
    %c7 = arith.constant 7 : i64
    %s = idr.con @S::@B(%c6, %c7) : (i64, i64) -> !idr.data<@S>
    %a = func.call @area(%s) : (!idr.data<@S>) -> i64
    return %a : i64
  }
}
