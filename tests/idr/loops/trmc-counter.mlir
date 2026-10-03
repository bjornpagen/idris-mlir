// RUN: idris-mlir-opt %s --idr-rc --idr-trmc --idr-tail-loops --idr-expect=holds=constant-stack=@replicate,constant-stack=@take -o /dev/null
// Data.List's replicate and take: a constructor around a call of the
// function itself on the predecessor of a natural, which the function then
// no longer needs. Were the parameter borrowed, the predecessor would be
// dropped after the call, between the call and the constructor, where
// idr-trmc moves no call past. Borrow inference counts such a call as the
// tail call idr-trmc makes it, and the parameter is owned: both functions
// become loops that write each cell to the destination they got.
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  func.func private @replicate(%n: !idr.nat, %x: i64) -> !idr.box<@List> {
    %nil = idr.constant #idr.con<@List::@Nil, []> : !idr.box<@List>
    %r = idr.match_lit %n : !idr.nat -> (!idr.box<@List>) {
    case #idr.big<"0"> {
      idr.yield %nil : !idr.box<@List>
    }
    default {
      %m = idr.big.pred %n
      %t = func.call @replicate(%m, %x) : (!idr.nat, i64) -> !idr.box<@List>
      %c = idr.con @List::@Cons(%x, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
      idr.yield %c : !idr.box<@List>
    }
    }
    return %r : !idr.box<@List>
  }
  func.func private @take(%n: !idr.nat, %l: !idr.box<@List>) -> !idr.box<@List> {
    %nil = idr.constant #idr.con<@List::@Nil, []> : !idr.box<@List>
    %r = idr.match_lit %n : !idr.nat -> (!idr.box<@List>) {
    case #idr.big<"0"> {
      idr.yield %nil : !idr.box<@List>
    }
    default {
      %m = idr.big.pred %n
      %s = idr.match %l : !idr.box<@List> -> (!idr.box<@List>) {
      case @Cons(%h: i64, %rest: !idr.box<@List>) {
        %t = func.call @take(%m, %rest) : (!idr.nat, !idr.box<@List>) -> !idr.box<@List>
        %c = idr.con @List::@Cons(%h, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
        idr.yield %c : !idr.box<@List>
      }
      default {
        idr.yield %nil : !idr.box<@List>
      }
      }
      idr.yield %s : !idr.box<@List>
    }
    }
    return %r : !idr.box<@List>
  }
  func.func @Prog.main() -> i64 {
    %three = idr.constant #idr.big<"3"> : !idr.nat
    %one = arith.constant 1 : i64
    %l = func.call @replicate(%three, %one) : (!idr.nat, i64) -> !idr.box<@List>
    %t = func.call @take(%three, %l) : (!idr.nat, !idr.box<@List>) -> !idr.box<@List>
    %n = idr.match %t : !idr.box<@List> -> (i64) {
    case @Cons(%h: i64, %rest: !idr.box<@List>) {
      idr.yield %h : i64
    }
    default {
      %zero = arith.constant 0 : i64
      idr.yield %zero : i64
    }
    }
    return %n : i64
  }
}
