// RUN: idris-mlir-opt %s --idr-stack > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-stack | FileCheck %s
// A box that its function builds and only reads (match, idr.field,
// idr.tag) stays in the function's frame: idr-stack marks its con. So does
// one that reaches a read through a match's result or an arith.select. One
// that is returned, directly or through a match's result or a select,
// outlives the frame. A mark on a con that escapes is dropped: the pass
// decides every mark itself, and a second run changes nothing.

// CHECK-LABEL: idr.func @read(
// CHECK: con {{.*}}@MkP({{[^)]*}}) stack
// CHECK-LABEL: idr.func @returned(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func @yielded(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func @matched(
// CHECK: con {{.*}}@MkP({{[^)]*}}) stack
// CHECK-LABEL: idr.func @selected(
// CHECK-NOT: ) stack :
// CHECK: return
// CHECK-LABEL: idr.func @chosen(
// CHECK: con {{.*}}@MkP({{[^)]*}}) stack
// CHECK-LABEL: idr.func @stale(
// CHECK-NOT: ) stack :
// CHECK: return
!P = !idr.data<"P", plain [@MkP(i64, i64)]>
idr.program @local root(@Prog.main) stage(first) {
  idr.func @read(%a: i64, %b: i64) -> i64 {
    %p = idr.con !idr.box<!P> @MkP(%a : i64, %b : i64)
    %r = idr.match %p : !idr.box<!P> -> (i64) {
    case @MkP(%x: i64, %y: i64) {
      %s = arith.addi %x, %y : i64
      idr.yield %s : i64
    }
    }
    %t = idr.tag %p : !idr.box<!P>
    %f = idr.field %p : !idr.box<!P> @MkP[1] -> i64
    %u = arith.addi %r, %t : i64
    %v = arith.addi %u, %f : i64
    return %v : i64
  }
  idr.func @returned(%a: i64, %b: i64) -> !idr.box<!P> {
    %p = idr.con !idr.box<!P> @MkP(%a : i64, %b : i64)
    return %p : !idr.box<!P>
  }
  idr.func @yielded(%n: i64, %q: !idr.box<!P>) -> !idr.box<!P> {
    %r = idr.match_lit %n : i64 -> (!idr.box<!P>) {
    case 0 {
      %p = idr.con !idr.box<!P> @MkP(%n : i64, %n : i64)
      idr.yield %p : !idr.box<!P>
    }
    default {
      idr.yield %q : !idr.box<!P>
    }
    }
    return %r : !idr.box<!P>
  }
  idr.func @matched(%n: i64, %q: !idr.box<!P>) -> i64 {
    %r = idr.match_lit %n : i64 -> (!idr.box<!P>) {
    case 0 {
      %p = idr.con !idr.box<!P> @MkP(%n : i64, %n : i64)
      idr.yield %p : !idr.box<!P>
    }
    default {
      idr.yield %q : !idr.box<!P>
    }
    }
    %x = idr.field %r : !idr.box<!P> @MkP[0] -> i64
    return %x : i64
  }
  idr.func @selected(%c: i1, %a: i64, %q: !idr.box<!P>) -> !idr.box<!P> {
    %p = idr.con !idr.box<!P> @MkP(%a : i64, %a : i64)
    %s = arith.select %c, %q, %p : !idr.box<!P>
    return %s : !idr.box<!P>
  }
  idr.func @chosen(%c: i1, %a: i64, %q: !idr.box<!P>) -> i64 {
    %p = idr.con !idr.box<!P> @MkP(%a : i64, %a : i64)
    %s = arith.select %c, %q, %p : !idr.box<!P>
    %x = idr.field %s : !idr.box<!P> @MkP[0] -> i64
    return %x : i64
  }
  idr.func @stale(%a: i64) -> !idr.box<!P> {
    %p = idr.con !idr.box<!P> @MkP(%a : i64, %a : i64) stack
    return %p : !idr.box<!P>
  }
  idr.func @Prog.main() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
