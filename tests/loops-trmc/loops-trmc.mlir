// RUN: idris-mlir-opt %s --idr-trmc -o %t.trmc.mlir
// RUN: idris-mlir-opt %t.trmc.mlir --pass-pipeline='builtin.module(idr.program(idr.func(idr-tail-loops)),idr-expect{holds=constant-stack=@copy,constant-stack=@copyLin,constant-stack=@dup,constant-stack=@joined})' -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@depth -o /dev/null 2> %t.err && FileCheck %s --check-prefix=DEPTH < %t.err
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@peek -o /dev/null 2> %t.peek.err && FileCheck %s --check-prefix=PEEK < %t.peek.err
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// RUN: %differential %t.trmc.mlir %t.reference.mlir
// RUN: %differential %t.mlir %t.reference.mlir
// @copy returns a constructor around its own result: the constructor is
// built first, with the field a hole, and its destination goes to a
// clone that returns nothing and writes each cell to the destination it
// got; idr-tail-loops then makes the clone a loop, so the copy runs in
// constant stack. The cell that takes the result may be further in:
// @dup returns it inside a second cell, and @joined inside a cell built
// after a match each of whose regions builds its own cell around the
// result, and gives that cell's destination as one more result. @depth
// inspects its own result, and @peek the cell that holds it, before the
// cell is returned, so their calls stay and the stack grows with them.
// The result of a call may enter a grade on its way to the field: a grade
// has no runtime form, and goes with the call.
// DEPTH: expected constant-stack: {{.*}}@depth
// PEEK: expected constant-stack: {{.*}}@peek
//
// The copy writes the list it copies: the program copies [1, 2, 3, 4, 5]
// and writes the copy's sum, its length, and what @depth makes of it (each
// element the head of the rest's result, 0 at the end, so all 0), then
// the length of the linear list's copy, then the sum and the length of
// @dup's list (each element twice), of @joined's (each element x as 0, x,
// x, and 1 as 0, 1), and the sum of @peek's (each element twice, the head
// read off the cell that holds it); it means 15 5 0 0 30 10 29 14 30, as
// the REFERENCE lines after the module write, as written, after
// idr-trmc, and after idr-tail-loops. (The reference follows the module,
// whose stage the differential reads from the first idr.program line of
// the file.)
// STDIN:
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
  idr.func @dup(%xs: !idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>> attributes {total} {
    %r = idr.match %xs : !idr.q<many, borrow, !idr.box<!List>> -> (!idr.own<!idr.box<!List>>) {
    case @Nil() {
      %nil = idr.constant !idr.q<many, borrow, !idr.box<!List>> #idr.con<!List, @Nil, []>
      %o = idr.dup %nil : !idr.q<many, borrow, !idr.box<!List>>
      idr.yield %o : !idr.own<!idr.box<!List>>
    }
    case @Cons(%x: i64, %rest: !idr.q<many, borrow, !idr.box<!List>>) {
      %ys = idr.call @dup(%rest) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
      %cell0 = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
      %inner = idr.cell.init %cell0 : !idr.cell<!idr.box<!List>, @Cons> (%x : i64, %ys : !idr.own<!idr.box<!List>>)
      %cell1 = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
      %outer = idr.cell.init %cell1 : !idr.cell<!idr.box<!List>, @Cons> (%x : i64, %inner : !idr.own<!idr.box<!List>>)
      idr.yield %outer : !idr.own<!idr.box<!List>>
    }
    }
    return %r : !idr.own<!idr.box<!List>>
  }
  // 1 :: rest becomes 0 :: 1 :: rest, any other x :: rest 0 :: x :: x :: rest.
  idr.func @joined(%xs: !idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>> attributes {total} {
    %r = idr.match %xs : !idr.q<many, borrow, !idr.box<!List>> -> (!idr.own<!idr.box<!List>>) {
    case @Nil() {
      %nil = idr.constant !idr.q<many, borrow, !idr.box<!List>> #idr.con<!List, @Nil, []>
      %o = idr.dup %nil : !idr.q<many, borrow, !idr.box<!List>>
      idr.yield %o : !idr.own<!idr.box<!List>>
    }
    case @Cons(%x: i64, %rest: !idr.q<many, borrow, !idr.box<!List>>) {
      %ys = idr.call @joined(%rest) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
      %b = idr.match_lit %x : i64 -> (!idr.own<!idr.box<!List>>) {
      case 1 {
        %cell0 = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
        %one = idr.cell.init %cell0 : !idr.cell<!idr.box<!List>, @Cons> (%x : i64, %ys : !idr.own<!idr.box<!List>>)
        idr.yield %one : !idr.own<!idr.box<!List>>
      }
      default(%y: i64) {
        %cell0 = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
        %inner = idr.cell.init %cell0 : !idr.cell<!idr.box<!List>, @Cons> (%y : i64, %ys : !idr.own<!idr.box<!List>>)
        %cell1 = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
        %two = idr.cell.init %cell1 : !idr.cell<!idr.box<!List>, @Cons> (%y : i64, %inner : !idr.own<!idr.box<!List>>)
        idr.yield %two : !idr.own<!idr.box<!List>>
      }
      }
      %zero = arith.constant 0 : i64
      %cell2 = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
      %c = idr.cell.init %cell2 : !idr.cell<!idr.box<!List>, @Cons> (%zero : i64, %b : !idr.own<!idr.box<!List>>)
      idr.yield %c : !idr.own<!idr.box<!List>>
    }
    }
    return %r : !idr.own<!idr.box<!List>>
  }
  // x :: rest becomes h :: x :: rest', where h is the head of x :: rest',
  // read from the cell that holds the call's result before it is returned.
  idr.func @peek(%xs: !idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>> attributes {total} {
    %r = idr.match %xs : !idr.q<many, borrow, !idr.box<!List>> -> (!idr.own<!idr.box<!List>>) {
    case @Nil() {
      %nil = idr.constant !idr.q<many, borrow, !idr.box<!List>> #idr.con<!List, @Nil, []>
      %o = idr.dup %nil : !idr.q<many, borrow, !idr.box<!List>>
      idr.yield %o : !idr.own<!idr.box<!List>>
    }
    case @Cons(%x: i64, %rest: !idr.q<many, borrow, !idr.box<!List>>) {
      %ys = idr.call @peek(%rest) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
      %cell0 = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
      %c = idr.cell.init %cell0 : !idr.cell<!idr.box<!List>, @Cons> (%x : i64, %ys : !idr.own<!idr.box<!List>>)
      %v = idr.borrow %c : !idr.own<!idr.box<!List>>
      %h = idr.match %v : !idr.q<many, borrow, !idr.box<!List>> -> (i64) {
      case @Nil() {
        %zero = arith.constant 0 : i64
        idr.yield %zero : i64
      }
      case @Cons(%y: i64, %more: !idr.q<many, borrow, !idr.box<!List>>) {
        idr.yield %y : i64
      }
      }
      %cell1 = idr.cell.new : !idr.cell<!idr.box<!List>, @Cons>
      %d = idr.cell.init %cell1 : !idr.cell<!idr.box<!List>, @Cons> (%h : i64, %c : !idr.own<!idr.box<!List>>)
      idr.yield %d : !idr.own<!idr.box<!List>>
    }
    }
    return %r : !idr.own<!idr.box<!List>>
  }
  // The sum and the length of a list, which only read it.
  idr.func @sum(%l: !idr.q<many, borrow, !idr.box<!List>>, %acc: i64, %n: i64) -> (i64, i64) attributes {total} {
    %r:2 = idr.match %l : !idr.q<many, borrow, !idr.box<!List>> -> (i64, i64) {
    case @Nil() {
      idr.yield %acc, %n : i64, i64
    }
    case @Cons(%h: i64, %t: !idr.q<many, borrow, !idr.box<!List>>) {
      %a = arith.addi %acc, %h : i64
      %one = arith.constant 1 : i64
      %m = arith.addi %n, %one : i64
      %s:2 = idr.call @sum(%t, %a, %m) : (!idr.q<many, borrow, !idr.box<!List>>, i64, i64) -> (i64, i64)
      idr.yield %s#0, %s#1 : i64, i64
    }
    }
    return %r#0, %r#1 : i64, i64
  }
  idr.func @lengthLin(%l: !idr.q<many, borrow, !idr.box<!LList>>, %n: i64) -> i64 attributes {total} {
    %r = idr.match %l : !idr.q<many, borrow, !idr.box<!LList>> -> (i64) {
    case @LNil() {
      idr.yield %n : i64
    }
    case @LCons(%h: i64, %t: !idr.q<many, borrow, !idr.box<!LList>>) {
      %one = arith.constant 1 : i64
      %m = arith.addi %n, %one : i64
      %s = idr.call @lengthLin(%t, %m) : (!idr.q<many, borrow, !idr.box<!LList>>, i64) -> i64
      idr.yield %s : i64
    }
    }
    return %r : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %xs = idr.constant !idr.q<many, borrow, !idr.box<!List>> #idr.con<!List, @Cons, [1, #idr.con<!List, @Cons, [2, #idr.con<!List, @Cons, [3, #idr.con<!List, @Cons, [4, #idr.con<!List, @Cons, [5, #idr.con<!List, @Nil, []>]>]>]>]>]>
    %a = idr.call @copy(%xs) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
    %va = idr.borrow %a : !idr.own<!idr.box<!List>>
    %b = idr.call @depth(%va) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
    %zero = arith.constant 0 : i64
    %s:2 = idr.call @sum(%va, %zero, %zero) : (!idr.q<many, borrow, !idr.box<!List>>, i64, i64) -> (i64, i64)
    %vb = idr.borrow %b : !idr.own<!idr.box<!List>>
    %d:2 = idr.call @sum(%vb, %zero, %zero) : (!idr.q<many, borrow, !idr.box<!List>>, i64, i64) -> (i64, i64)
    idr.drop %a : !idr.own<!idr.box<!List>>
    idr.drop %b : !idr.own<!idr.box<!List>>
    %ls = idr.constant !idr.q<many, borrow, !idr.box<!LList>> #idr.con<!LList, @LNil, []>
    %c = idr.call @copyLin(%ls) : (!idr.q<many, borrow, !idr.box<!LList>>) -> !idr.own<!idr.box<!LList>>
    %vc = idr.borrow %c : !idr.own<!idr.box<!LList>>
    %k = idr.call @lengthLin(%vc, %zero) : (!idr.q<many, borrow, !idr.box<!LList>>, i64) -> i64
    idr.drop %c : !idr.own<!idr.box<!LList>>
    %e = idr.call @dup(%xs) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
    %ve = idr.borrow %e : !idr.own<!idr.box<!List>>
    %de:2 = idr.call @sum(%ve, %zero, %zero) : (!idr.q<many, borrow, !idr.box<!List>>, i64, i64) -> (i64, i64)
    idr.drop %e : !idr.own<!idr.box<!List>>
    %j = idr.call @joined(%xs) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
    %vj = idr.borrow %j : !idr.own<!idr.box<!List>>
    %dj:2 = idr.call @sum(%vj, %zero, %zero) : (!idr.q<many, borrow, !idr.box<!List>>, i64, i64) -> (i64, i64)
    idr.drop %j : !idr.own<!idr.box<!List>>
    %p = idr.call @peek(%xs) : (!idr.q<many, borrow, !idr.box<!List>>) -> !idr.own<!idr.box<!List>>
    %vp = idr.borrow %p : !idr.own<!idr.box<!List>>
    %dp:2 = idr.call @sum(%vp, %zero, %zero) : (!idr.q<many, borrow, !idr.box<!List>>, i64, i64) -> (i64, i64)
    idr.drop %p : !idr.own<!idr.box<!List>>
    %sp = arith.constant 32 : i32
    %w1 = idr.io.put_sint %s#0, %w : i64
    %w2 = idr.io.put_char %sp, %w1
    %w3 = idr.io.put_sint %s#1, %w2 : i64
    %w4 = idr.io.put_char %sp, %w3
    %w5 = idr.io.put_sint %d#0, %w4 : i64
    %w6 = idr.io.put_char %sp, %w5
    %w7 = idr.io.put_sint %k, %w6 : i64
    %w8 = idr.io.put_char %sp, %w7
    %w9 = idr.io.put_sint %de#0, %w8 : i64
    %w10 = idr.io.put_char %sp, %w9
    %w11 = idr.io.put_sint %de#1, %w10 : i64
    %w12 = idr.io.put_char %sp, %w11
    %w13 = idr.io.put_sint %dj#0, %w12 : i64
    %w14 = idr.io.put_char %sp, %w13
    %w15 = idr.io.put_sint %dj#1, %w14 : i64
    %w16 = idr.io.put_char %sp, %w15
    %w17 = idr.io.put_sint %dp#0, %w16 : i64
    return %w17 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@Main.main) stage(first) {
// REFERENCE:   idr.func @Main.main(%w: !idr.world) -> !idr.world {
// REFERENCE:     %s = idr.constant !idr.str "15 5 0 0 30 10 29 14 30"
// REFERENCE:     %w1 = idr.io.put_str %s, %w
// REFERENCE:     return %w1 : !idr.world
// REFERENCE:   }
// REFERENCE: }
