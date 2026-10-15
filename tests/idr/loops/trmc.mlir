// RUN: idris-mlir-opt %s --idr-trmc -o %t.trmc.mlir
// RUN: FileCheck %s < %t.trmc.mlir
// RUN: idris-mlir-opt %t.trmc.mlir --idr-tail-loops --idr-expect=holds=constant-stack=@copy,constant-stack=@copyLin -o %t.mlir
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=constant-stack=@depth -o /dev/null 2> %t.err && FileCheck %s --check-prefix=DEPTH < %t.err
// NEEDS-ACCEPTANCE: the copies are named <owner>.trmc.<16 hex digits> from their keys (C21); check that the patterns match them.
// @copy returns a constructor around its own result: the constructor is
// built first, with the field pending, and its destination goes to a
// clone that returns nothing and writes each cell to the destination it
// got; idr-tail-loops then makes the clone a loop, so the copy runs in
// constant stack. @depth inspects its own result, so its call stays and
// the stack grows with it.
// CHECK-LABEL: idr.func private @copy(
// CHECK: %[[P:.*]] = idr.dest.pending : !idr.own<!idr.box<!List>>
// CHECK: %[[C:.*]] = {{(idr\.)?}}con @Cons(%{{.*}}, %[[P]])
// CHECK: %[[V:.*]] = {{(idr\.)?}}borrow %[[C]]
// CHECK: %[[D:.*]] = idr.dest.of %[[V]][@Cons, 1]
// CHECK: call @{{copy\.trmc\.[0-9a-f]+}}(%{{.*}}, %[[D]]) : (!idr.box<!List>, !idr.dest<!idr.box<!List>>) -> ()
// CHECK: idr.yield %[[C]]
// CHECK-LABEL: idr.func private @{{copy\.trmc\.[0-9a-f]+}}(
// CHECK-SAME: %{{.*}}: !idr.box<!List>, %[[H:[a-z0-9_]+]]: !idr.dest<!idr.box<!List>>) attributes
// CHECK: case @Nil() {
// CHECK: idr.dest.write %[[H]], %{{.*}} : <!idr.box<!List>>
// CHECK: case @Cons(
// CHECK: %[[C2:.*]] = {{(idr\.)?}}con @Cons(
// CHECK: %[[V2:.*]] = {{(idr\.)?}}borrow %[[C2]]
// CHECK-NEXT: %[[D2:.*]] = idr.dest.of %[[V2]][@Cons, 1]
// CHECK-NEXT: idr.dest.write %[[H]], %[[C2]]
// CHECK-NEXT: call @{{copy\.trmc\.[0-9a-f]+}}(%{{.*}}, %[[D2]])
// CHECK-NEXT: idr.yield
// CHECK-NOT: idr.func private @{{depth\.trmc\.[0-9a-f]+}}(
// The result of a call may enter a grade on its way to the field: a grade
// has no runtime form, and goes with the call.
// CHECK-LABEL: idr.func private @copyLin(
// CHECK: %[[PL:.*]] = idr.dest.pending : !idr.q<one, own, !idr.box<!LList>>
// CHECK: con @LCons(%{{.*}}, %[[PL]])
// CHECK: call @{{copyLin\.trmc\.[0-9a-f]+}}(
// CHECK-LABEL: idr.func private @{{copyLin\.trmc\.[0-9a-f]+}}(
// DEPTH: expected constant-stack: the stack grows with the recursion of @depth
!List = !idr.data<"List", list [@Nil(), @Cons(i64, !idr.box<!idr.data<"List">>)]>
!LList = !idr.data<"LList", list [@LNil(), @LCons(i64, !idr.lin<!idr.box<!idr.data<"LList">>>)]>
module {
  idr.func private @copy(%xs: !idr.box<!List>) -> !idr.own<!idr.box<!List>> attributes {total} {
    %r = idr.match %xs : !idr.box<!List> -> (!idr.own<!idr.box<!List>>) {
    case @Nil() {
      %nil = idr.constant #idr.con<@Nil, []> : !idr.box<!List>
      %o = idr.dup %nil : !idr.box<!List>
      idr.yield %o : !idr.own<!idr.box<!List>>
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %ys = idr.call @copy(%rest) : (!idr.box<!List>) -> !idr.own<!idr.box<!List>>
      %c = idr.con @Cons(%x, %ys) : (i64, !idr.own<!idr.box<!List>>) -> !idr.own<!idr.box<!List>>
      idr.yield %c : !idr.own<!idr.box<!List>>
    }
    }
    return %r : !idr.own<!idr.box<!List>>
  }
  idr.func private @copyLin(%xs: !idr.box<!LList>) -> !idr.own<!idr.box<!LList>> attributes {total} {
    %r = idr.match %xs : !idr.box<!LList> -> (!idr.own<!idr.box<!LList>>) {
    case @LNil() {
      %nil = idr.constant #idr.con<@LNil, []> : !idr.box<!LList>
      %o = idr.dup %nil : !idr.box<!LList>
      idr.yield %o : !idr.own<!idr.box<!LList>>
    }
    case @LCons(%x: i64, %rest: !idr.box<!LList>) {
      %ys = idr.call @copyLin(%rest) : (!idr.box<!LList>) -> !idr.own<!idr.box<!LList>>
      %l = idr.lin.enter %ys : !idr.q<one, own, !idr.box<!LList>>
      %c = idr.con @LCons(%x, %l) : (i64, !idr.q<one, own, !idr.box<!LList>>) -> !idr.own<!idr.box<!LList>>
      idr.yield %c : !idr.own<!idr.box<!LList>>
    }
    }
    return %r : !idr.own<!idr.box<!LList>>
  }
  idr.func private @depth(%xs: !idr.box<!List>) -> !idr.own<!idr.box<!List>> attributes {total} {
    %r = idr.match %xs : !idr.box<!List> -> (!idr.own<!idr.box<!List>>) {
    case @Nil() {
      %nil = idr.constant #idr.con<@Nil, []> : !idr.box<!List>
      %o = idr.dup %nil : !idr.box<!List>
      idr.yield %o : !idr.own<!idr.box<!List>>
    }
    case @Cons(%x: i64, %rest: !idr.box<!List>) {
      %ys = idr.call @depth(%rest) : (!idr.box<!List>) -> !idr.own<!idr.box<!List>>
      %v = idr.borrow %ys : !idr.own<!idr.box<!List>>
      %n = idr.match %v : !idr.box<!List> -> (i64) {
      case @Nil() {
        %zero = arith.constant 0 : i64
        idr.yield %zero : i64
      }
      case @Cons(%y: i64, %more: !idr.box<!List>) {
        idr.yield %y : i64
      }
      }
      %c = idr.con @Cons(%n, %ys) : (i64, !idr.own<!idr.box<!List>>) -> !idr.own<!idr.box<!List>>
      idr.yield %c : !idr.own<!idr.box<!List>>
    }
    }
    return %r : !idr.own<!idr.box<!List>>
  }
  idr.func @Main.main() -> i64 {
    %xs = idr.constant #idr.con<@Cons, [1, #idr.con<@Nil, []>]> : !idr.box<!List>
    %a = idr.call @copy(%xs) : (!idr.box<!List>) -> !idr.own<!idr.box<!List>>
    %va = idr.borrow %a : !idr.own<!idr.box<!List>>
    %b = idr.call @depth(%va) : (!idr.box<!List>) -> !idr.own<!idr.box<!List>>
    idr.drop %a : !idr.own<!idr.box<!List>>
    idr.drop %b : !idr.own<!idr.box<!List>>
    %ls = idr.constant #idr.con<@LNil, []> : !idr.box<!LList>
    %c = idr.call @copyLin(%ls) : (!idr.box<!LList>) -> !idr.own<!idr.box<!LList>>
    idr.drop %c : !idr.own<!idr.box<!LList>>
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
