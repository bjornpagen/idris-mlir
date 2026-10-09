// RUN: idris-mlir-opt %s --idr-trmc -o %t.trmc.mlir
// RUN: FileCheck %s < %t.trmc.mlir
// RUN: idris-mlir-opt %t.trmc.mlir --idr-tail-loops --idr-expect=holds=constant-stack=@copy,constant-stack=@copyLin -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@depth -o /dev/null 2> %t.err && FileCheck %s --check-prefix=DEPTH < %t.err
// @copy returns a constructor around its own result: the constructor is
// built first, with the field pending, and its destination goes to a
// clone that returns nothing and writes each cell to the destination it
// got; idr-tail-loops then makes the clone a loop, so the copy runs in
// constant stack. @depth inspects its own result, so its call stays and
// the stack grows with it.
// CHECK-LABEL: func.func private @copy(
// CHECK: %[[P:.*]] = idr.dest.pending : !idr.own<!idr.box<@List>>
// CHECK: %[[C:.*]] = idr.con @List::@Cons(%{{.*}}, %[[P]])
// CHECK: %[[V:.*]] = idr.borrow %[[C]]
// CHECK: %[[D:.*]] = idr.dest.of %[[V]][@Cons, 1]
// CHECK: func.call @copy$trmc(%{{.*}}, %[[D]]) : (!idr.box<@List>, !idr.dest<!idr.box<@List>>) -> ()
// CHECK: idr.yield %[[C]]
// CHECK-LABEL: func.func private @copy$trmc(
// CHECK-SAME: %{{.*}}: !idr.box<@List>, %[[H:[a-z0-9_]+]]: !idr.dest<!idr.box<@List>>) attributes
// CHECK: case @Nil() {
// CHECK: idr.dest.write %[[H]], %{{.*}} : <!idr.box<@List>>
// CHECK: case @Cons(
// CHECK: %[[C2:.*]] = idr.con @List::@Cons(
// CHECK: %[[V2:.*]] = idr.borrow %[[C2]]
// CHECK-NEXT: %[[D2:.*]] = idr.dest.of %[[V2]][@Cons, 1]
// CHECK-NEXT: idr.dest.write %[[H]], %[[C2]]
// CHECK-NEXT: func.call @copy$trmc(%{{.*}}, %[[D2]])
// CHECK-NEXT: idr.yield
// CHECK-NOT: func.func private @depth$trmc(
// The result of a call may enter a grade on its way to the field: a grade
// has no runtime form, and goes with the call.
// CHECK-LABEL: func.func private @copyLin(
// CHECK: %[[PL:.*]] = idr.dest.pending : !idr.q<one, own, !idr.box<@LList>>
// CHECK: idr.con @LList::@LCons(%{{.*}}, %[[PL]])
// CHECK: func.call @copyLin$trmc(
// CHECK-LABEL: func.func private @copyLin$trmc(
// DEPTH: expected constant-stack: the stack grows with the recursion of @depth
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  func.func private @copy(%xs: !idr.box<@List>) -> !idr.own<!idr.box<@List>> attributes {idr.total} {
    %r = idr.match %xs : !idr.box<@List> -> (!idr.own<!idr.box<@List>>) {
    case @Nil() {
      %nil = idr.constant #idr.con<@List::@Nil, []> : !idr.box<@List>
      %o = idr.dup %nil : !idr.box<@List>
      idr.yield %o : !idr.own<!idr.box<@List>>
    }
    case @Cons(%x: i64, %rest: !idr.box<@List>) {
      %ys = func.call @copy(%rest) : (!idr.box<@List>) -> !idr.own<!idr.box<@List>>
      %c = idr.con @List::@Cons(%x, %ys) : (i64, !idr.own<!idr.box<@List>>) -> !idr.own<!idr.box<@List>>
      idr.yield %c : !idr.own<!idr.box<@List>>
    }
    }
    return %r : !idr.own<!idr.box<@List>>
  }
  idr.data @LList box {
    idr.ctor @LNil ()
    idr.ctor @LCons (i64, !idr.lin<!idr.box<@LList>>)
  }
  func.func private @copyLin(%xs: !idr.box<@LList>) -> !idr.own<!idr.box<@LList>> attributes {idr.total} {
    %r = idr.match %xs : !idr.box<@LList> -> (!idr.own<!idr.box<@LList>>) {
    case @LNil() {
      %nil = idr.constant #idr.con<@LList::@LNil, []> : !idr.box<@LList>
      %o = idr.dup %nil : !idr.box<@LList>
      idr.yield %o : !idr.own<!idr.box<@LList>>
    }
    case @LCons(%x: i64, %rest: !idr.box<@LList>) {
      %ys = func.call @copyLin(%rest) : (!idr.box<@LList>) -> !idr.own<!idr.box<@LList>>
      %l = idr.lin.enter %ys : !idr.q<one, own, !idr.box<@LList>>
      %c = idr.con @LList::@LCons(%x, %l) : (i64, !idr.q<one, own, !idr.box<@LList>>) -> !idr.own<!idr.box<@LList>>
      idr.yield %c : !idr.own<!idr.box<@LList>>
    }
    }
    return %r : !idr.own<!idr.box<@LList>>
  }
  func.func private @depth(%xs: !idr.box<@List>) -> !idr.own<!idr.box<@List>> attributes {idr.total} {
    %r = idr.match %xs : !idr.box<@List> -> (!idr.own<!idr.box<@List>>) {
    case @Nil() {
      %nil = idr.constant #idr.con<@List::@Nil, []> : !idr.box<@List>
      %o = idr.dup %nil : !idr.box<@List>
      idr.yield %o : !idr.own<!idr.box<@List>>
    }
    case @Cons(%x: i64, %rest: !idr.box<@List>) {
      %ys = func.call @depth(%rest) : (!idr.box<@List>) -> !idr.own<!idr.box<@List>>
      %v = idr.borrow %ys : !idr.own<!idr.box<@List>>
      %n = idr.match %v : !idr.box<@List> -> (i64) {
      case @Nil() {
        %zero = arith.constant 0 : i64
        idr.yield %zero : i64
      }
      case @Cons(%y: i64, %more: !idr.box<@List>) {
        idr.yield %y : i64
      }
      }
      %c = idr.con @List::@Cons(%n, %ys) : (i64, !idr.own<!idr.box<@List>>) -> !idr.own<!idr.box<@List>>
      idr.yield %c : !idr.own<!idr.box<@List>>
    }
    }
    return %r : !idr.own<!idr.box<@List>>
  }
  func.func @Main.main() -> i64 {
    %xs = idr.constant #idr.con<@List::@Cons, [1, #idr.con<@List::@Nil, []>]> : !idr.box<@List>
    %a = func.call @copy(%xs) : (!idr.box<@List>) -> !idr.own<!idr.box<@List>>
    %va = idr.borrow %a : !idr.own<!idr.box<@List>>
    %b = func.call @depth(%va) : (!idr.box<@List>) -> !idr.own<!idr.box<@List>>
    idr.drop %a : !idr.own<!idr.box<@List>>
    idr.drop %b : !idr.own<!idr.box<@List>>
    %ls = idr.constant #idr.con<@LList::@LNil, []> : !idr.box<@LList>
    %c = func.call @copyLin(%ls) : (!idr.box<@LList>) -> !idr.own<!idr.box<@LList>>
    idr.drop %c : !idr.own<!idr.box<@LList>>
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
