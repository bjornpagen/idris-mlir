// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --idr-trmc --mlir-disable-threading -mlir-debug-counter=idr-trmc-clone-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --idr-trmc -o %t.done.mlir
// RUN: %status 1 diff %t.none.mlir %t.done.mlir
// RUN: %differential %s %t.done.mlir
// With every action skipped the pass is the identity, and with none it
// changes the module. The root copies lists made from the byte it reads
// and prints their digits, and the program prints after the pass what it
// printed before, on every byte.
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
!LList = !idr.data<"LList", list [@LNil() nil, @LCons(i64, !idr.lin<!idr.box<!idr.data<"LList">>>) cons]>
idr.program @trmc root(@Main.main) stage(owned) {
  idr.func @copy(%xs: !idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>> attributes {total} {
    %r = idr.match %xs : !idr.q<many, borrow, !idr.box<!List>> -> (!idr.own<!idr.box<!List>>) {
    case @Nil() {
      %nil = idr.constant !idr.q<many, borrow, !idr.box<!List>> #idr.con<!List, @Nil, []>
      %o = idr.dup %nil : !idr.q<many, borrow, !idr.box<!List>>
      idr.yield %o : !idr.own<!idr.box<!List>>
    }
    case @Cons(%x: i64, %rest: !idr.q<many, borrow, !idr.box<!List>>) {
      %ys = idr.call @copy(%rest) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
      %cell0 = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
      %c = idr.cell.init %cell0 : !idr.cell<!idr.box<!List>, @Cons> (%x : i64, %ys : !idr.own<!idr.box<!List>>)
      idr.yield %c : !idr.own<!idr.box<!List>>
    }
    }
    return %r : !idr.own<!idr.box<!List>>
  }
  idr.func @copyLin(%xs: !idr.q<many, borrow, !idr.box<!LList>>) -> !idr.own<!idr.box<!LList>> attributes {total} {
    %r = idr.match %xs : !idr.q<many, borrow, !idr.box<!LList>> -> (!idr.own<!idr.box<!LList>>) {
    case @LNil() {
      %nil = idr.constant !idr.q<many, borrow, !idr.box<!LList>> #idr.con<!LList, @LNil, []>
      %o = idr.dup %nil : !idr.q<many, borrow, !idr.box<!LList>>
      idr.yield %o : !idr.own<!idr.box<!LList>>
    }
    case @LCons(%x: i64, %rest: !idr.q<many, borrow, !idr.box<!LList>>) {
      %ys = idr.call @copyLin(%rest) : (!idr.q<many, borrow, !idr.box<!LList>>) -> !idr.own<!idr.box<!LList>>
      %l = idr.lin.enter %ys : !idr.q<one, own, !idr.box<!LList>>
      %cell1 = idr.cell.new : !idr.cell<!idr.box<!LList>, @LCons>
      %c = idr.cell.init %cell1 : !idr.cell<!idr.box<!LList>, @LCons> (%x : i64, %l : !idr.q<one, own, !idr.box<!LList>>)
      idr.yield %c : !idr.own<!idr.box<!LList>>
    }
    }
    return %r : !idr.own<!idr.box<!LList>>
  }
  idr.func @depth(%xs: !idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>> attributes {total} {
    %r = idr.match %xs : !idr.q<many, borrow, !idr.box<!List>> -> (!idr.own<!idr.box<!List>>) {
    case @Nil() {
      %nil = idr.constant !idr.q<many, borrow, !idr.box<!List>> #idr.con<!List, @Nil, []>
      %o = idr.dup %nil : !idr.q<many, borrow, !idr.box<!List>>
      idr.yield %o : !idr.own<!idr.box<!List>>
    }
    case @Cons(%x: i64, %rest: !idr.q<many, borrow, !idr.box<!List>>) {
      %ys = idr.call @depth(%rest) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
      %v = idr.borrow %ys : !idr.own<!idr.box<!List>>
      %n = idr.match %v : !idr.q<many, borrow, !idr.box<!List>> -> (i64) {
      case @Nil() {
        %zero = arith.constant 0 : i64
        idr.yield %zero : i64
      }
      case @Cons(%y: i64, %more: !idr.q<many, borrow, !idr.box<!List>>) {
        idr.yield %y : i64
      }
      }
      %cell2 = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
      %c = idr.cell.init %cell2 : !idr.cell<!idr.box<!List>, @Cons> (%n : i64, %ys : !idr.own<!idr.box<!List>>)
      idr.yield %c : !idr.own<!idr.box<!List>>
    }
    }
    return %r : !idr.own<!idr.box<!List>>
  }
  idr.func @sum(%xs: !idr.q<many, borrow, !idr.box<!List>>, %acc: i64) -> i64 attributes {total} {
    %r = idr.match %xs : !idr.q<many, borrow, !idr.box<!List>> -> (i64) {
    case @Nil() {
      idr.yield %acc : i64
    }
    case @Cons(%x: i64, %rest: !idr.q<many, borrow, !idr.box<!List>>) {
      %ten = arith.constant 10 : i64
      %shifted = arith.muli %acc, %ten : i64
      %a = arith.addi %shifted, %x : i64
      %s = idr.call @sum(%rest, %a) : (!idr.q<many, borrow, !idr.box<!List>>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  // The program's root copies a list of three cells made from the byte it
  // reads, and the list of each cell's next element, and prints the digits
  // of each; and copies a linear list.
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %ch, %w1 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c3 = arith.constant 3 : i64
    %c4 = arith.constant 4 : i64
    %c7 = arith.constant 7 : i64
    %x = arith.remui %b, %c7 : i64
    %y = arith.remui %b, %c3 : i64
    %z = arith.addi %y, %c4 : i64
    %nil = idr.con !idr.own<!idr.box<!List>> @Nil()
    %l1.cell = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
    %l1 = idr.cell.init %l1.cell : !idr.cell<!idr.box<!List>, @Cons> (%z : i64, %nil : !idr.own<!idr.box<!List>>)
    %l2.cell = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
    %l2 = idr.cell.init %l2.cell : !idr.cell<!idr.box<!List>, @Cons> (%y : i64, %l1 : !idr.own<!idr.box<!List>>)
    %l3.cell = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
    %l3 = idr.cell.init %l3.cell : !idr.cell<!idr.box<!List>, @Cons> (%x : i64, %l2 : !idr.own<!idr.box<!List>>)
    %xs = idr.borrow %l3 : !idr.own<!idr.box<!List>>
    %a = idr.call @copy(%xs) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
    %va = idr.borrow %a : !idr.own<!idr.box<!List>>
    %b2 = idr.call @depth(%va) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
    %zero = arith.constant 0 : i64
    %one = arith.constant 1 : i64
    %sa = idr.call @sum(%va, %one) : (!idr.q<many, borrow, !idr.box<!List>>, i64) -> i64
    %vb = idr.borrow %b2 : !idr.own<!idr.box<!List>>
    %sb = idr.call @sum(%vb, %one) : (!idr.q<many, borrow, !idr.box<!List>>, i64) -> i64
    %w2 = idr.io.put_sint %sa, %w1 : i64
    %w3 = idr.io.put_sint %sb, %w2 : i64
    idr.drop %a : !idr.own<!idr.box<!List>>
    idr.drop %b2 : !idr.own<!idr.box<!List>>
    idr.drop %l3 : !idr.own<!idr.box<!List>>
    %ls = idr.constant !idr.q<many, borrow, !idr.box<!LList>> #idr.con<!LList, @LNil, []>
    %c = idr.call @copyLin(%ls) : (!idr.q<many, borrow, !idr.box<!LList>>) -> !idr.own<!idr.box<!LList>>
    idr.drop %c : !idr.own<!idr.box<!LList>>
    return %w3 : !idr.world
  }
}
