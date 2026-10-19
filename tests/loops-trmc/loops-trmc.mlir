// RUN: idris-mlir-opt %s --idr-trmc -o %t.trmc.mlir
// RUN: idris-mlir-opt %t.trmc.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@copy,constant-stack=@copyLin})' -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@depth -o /dev/null 2> %t.err && FileCheck %s --check-prefix=DEPTH < %t.err
// @copy returns a constructor around its own result: the constructor is
// built first, with the field a hole, and its destination goes to a
// clone that returns nothing and writes each cell to the destination it
// got; idr-tail-loops then makes the clone a loop, so the copy runs in
// constant stack. @depth inspects its own result, so its call stays and
// the stack grows with it.
// The result of a call may enter a grade on its way to the field: a grade
// has no runtime form, and goes with the call.
// DEPTH: expected constant-stack: {{.*}}@depth
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
  idr.func @Main.main() -> i64 {
    %xs = idr.constant !idr.q<many, borrow, !idr.box<!List>> #idr.con<!List, @Cons, [1, #idr.con<!List, @Nil, []>]>
    %a = idr.call @copy(%xs) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
    %va = idr.borrow %a : !idr.own<!idr.box<!List>>
    %b = idr.call @depth(%va) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
    idr.drop %a : !idr.own<!idr.box<!List>>
    idr.drop %b : !idr.own<!idr.box<!List>>
    %ls = idr.constant !idr.q<many, borrow, !idr.box<!LList>> #idr.con<!LList, @LNil, []>
    %c = idr.call @copyLin(%ls) : (!idr.q<many, borrow, !idr.box<!LList>>) -> !idr.own<!idr.box<!LList>>
    idr.drop %c : !idr.own<!idr.box<!LList>>
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
