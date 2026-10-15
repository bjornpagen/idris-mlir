// RUN: idris-mlir-opt %s --idr-rc --idr-expect=holds=counts-nothing=@growLeft,reuses-in-place=@growLeft,tests-nothing=@growLeft,counts-nothing=@growLeft2,reuses-in-place=@growLeft2 -o /dev/null
// RUN: idris-mlir-opt %s --idr-rc --idr-lower | FileCheck %s
// A constructor rebuilt in the cell of the one taken apart, with one field
// changed: the fields given back as the take gave them are in the cell
// already, with the reference it held all along. In the owned stage they
// move out of the take and into the reuse, so nothing is counted for them
// (counts-nothing); the lowering stores neither them nor the header, only
// the field that changed. Where the box may be shared, the take tests it
// and the token may be null: the kept fields are then stored into the
// fresh cell only, and the cell that was the box's gets the one store. A
// reuse of another constructor of the same size writes its header and
// every field.
// CHECK-LABEL: func.func private @growLeft(
// CHECK-NOT: llvm.store
// CHECK-NOT: idris_rt_cell
// CHECK: call @wrap
// CHECK-COUNT-1: llvm.store
// CHECK-NOT: llvm.store
// CHECK-NOT: idris_rt_cell
// CHECK: return
// CHECK-LABEL: func.func private @growLeft2(
// CHECK: scf.if
// CHECK: idris_rt_inc
// CHECK: idris_rt_dec
// CHECK-NOT: llvm.store
// CHECK: call @wrap
// CHECK-NOT: llvm.store
// CHECK: scf.if
// CHECK: llvm.call @idris_rt_cell(
// CHECK-COUNT-2: llvm.store
// CHECK: } else {
// CHECK-NEXT: scf.yield
// CHECK: }
// CHECK-COUNT-1: llvm.store
// CHECK-NOT: llvm.store
// CHECK: return
// CHECK-LABEL: func.func private @swap(
// CHECK-NOT: idris_rt_cell
// CHECK-COUNT-5: llvm.store
// CHECK-NOT: llvm.store
// CHECK: return
!T = !idr.data<"T", plain [@Leaf(), @Node(!idr.box<!idr.data<"T">>, i64, !idr.box<!idr.data<"T">>)]>
!P = !idr.data<"P", plain [@None(), @Pair(!idr.box<!T>, !idr.box<!T>, i64)]>
module {
  // A cell of @Pair is as large as one of @Node.
  idr.func private @wrap(%x: !idr.box<!T>) -> !idr.box<!T> {
    %leaf = idr.constant #idr.con<@Leaf, []> : !idr.box<!T>
    %z = arith.constant 0 : i64
    %n = idr.con @Node(%x, %z, %leaf) : (!idr.box<!T>, i64, !idr.box<!T>) -> !idr.box<!T>
    return %n : !idr.box<!T>
  }
  // The left subtree changes; the key and the right subtree are kept.
  idr.func private @growLeft(%t: !idr.box<!T>) -> !idr.box<!T> {
    %r = idr.match %t : !idr.box<!T> -> (!idr.box<!T>) {
    case @Leaf() {
      idr.yield %t : !idr.box<!T>
    }
    case @Node(%l: !idr.box<!T>, %k: i64, %rt: !idr.box<!T>) {
      %l2 = idr.call @wrap(%l) : (!idr.box<!T>) -> !idr.box<!T>
      %n = idr.con @Node(%l2, %k, %rt) : (!idr.box<!T>, i64, !idr.box<!T>) -> !idr.box<!T>
      idr.yield %n : !idr.box<!T>
    }
    }
    return %r : !idr.box<!T>
  }
  // The same, on a tree its caller keeps a reference to.
  idr.func private @growLeft2(%t: !idr.box<!T>) -> !idr.box<!T> {
    %r = idr.match %t : !idr.box<!T> -> (!idr.box<!T>) {
    case @Leaf() {
      idr.yield %t : !idr.box<!T>
    }
    case @Node(%l: !idr.box<!T>, %k: i64, %rt: !idr.box<!T>) {
      %l2 = idr.call @wrap(%l) : (!idr.box<!T>) -> !idr.box<!T>
      %n = idr.con @Node(%l2, %k, %rt) : (!idr.box<!T>, i64, !idr.box<!T>) -> !idr.box<!T>
      idr.yield %n : !idr.box<!T>
    }
    }
    return %r : !idr.box<!T>
  }
  // Another constructor, of another type, in the node's cell.
  idr.func private @swap(%t: !idr.box<!T>) -> !idr.box<!P> {
    %r = idr.match %t : !idr.box<!T> -> (!idr.box<!P>) {
    case @Leaf() {
      %none = idr.constant #idr.con<@None, []> : !idr.box<!P>
      idr.yield %none : !idr.box<!P>
    }
    case @Node(%l: !idr.box<!T>, %k: i64, %rt: !idr.box<!T>) {
      %p = idr.con @Pair(%l, %rt, %k) : (!idr.box<!T>, !idr.box<!T>, i64) -> !idr.box<!P>
      idr.yield %p : !idr.box<!P>
    }
    }
    return %r : !idr.box<!P>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %x = arith.constant 7 : i64
    %leaf = idr.constant #idr.con<@Leaf, []> : !idr.box<!T>
    %t = idr.con @Node(%leaf, %x, %leaf) : (!idr.box<!T>, i64, !idr.box<!T>) -> !idr.box<!T>
    %g = idr.call @growLeft(%t) : (!idr.box<!T>) -> !idr.box<!T>
    %m = idr.con @Node(%leaf, %x, %leaf) : (!idr.box<!T>, i64, !idr.box<!T>) -> !idr.box<!T>
    %h = idr.call @growLeft2(%m) : (!idr.box<!T>) -> !idr.box<!T>
    %a = idr.tag %m : !idr.box<!T>
    %s = idr.con @Node(%leaf, %x, %leaf) : (!idr.box<!T>, i64, !idr.box<!T>) -> !idr.box<!T>
    %p = idr.call @swap(%s) : (!idr.box<!T>) -> !idr.box<!P>
    %b = idr.tag %g : !idr.box<!T>
    %c = idr.tag %h : !idr.box<!T>
    %d = idr.tag %p : !idr.box<!P>
    %ab = arith.addi %a, %b : i64
    %cd = arith.addi %c, %d : i64
    %sum = arith.addi %ab, %cd : i64
    %w2 = idr.io.put_int signed %sum, %w : i64
    return %w2 : !idr.world
  }
}
