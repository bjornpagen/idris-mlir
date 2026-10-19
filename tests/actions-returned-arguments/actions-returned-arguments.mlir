// RUN: idris-mlir-opt %s -o %t.none.mlir
// RUN: idris-mlir-opt %s --idr-returned-arguments --mlir-disable-threading -mlir-debug-counter=idr-returned-arguments-drop-count=0 -o %t.skipped.mlir
// RUN: diff %t.none.mlir %t.skipped.mlir
// RUN: idris-mlir-opt %s --idr-returned-arguments -o %t.done.mlir
// RUN: %status 1 diff %t.none.mlir %t.done.mlir
module {
  func.func @root(%p: !llvm.ptr, %m: i64) -> (!llvm.ptr, i64) {
    %v, %q = func.call @find(%p, %m, %m) : (!llvm.ptr, i64, i64) -> (i64, !llvm.ptr)
    %w, %r = func.call @sometimes(%q, %q, %m) : (!llvm.ptr, !llvm.ptr, i64) -> (i64, !llvm.ptr)
    %x, %s = func.call @named(%r, %w) : (!llvm.ptr, i64) -> (i64, !llvm.ptr)
    %f = func.constant @named : (!llvm.ptr, i64) -> (i64, !llvm.ptr)
    %y, %t = func.call_indirect %f(%s, %w) : (!llvm.ptr, i64) -> (i64, !llvm.ptr)
    %z, %u = func.call @loop(%t, %m) : (!llvm.ptr, i64) -> (i64, !llvm.ptr)
    return %u, %z : !llvm.ptr, i64
  }
  func.func private @find(%a: !llvm.ptr, %n: i64, %i: i64) -> (i64, !llvm.ptr) {
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %done = arith.cmpi eq, %i, %c0 : i64
    %r, %b = scf.if %done -> (i64, !llvm.ptr) {
      %k = arith.addi %n, %i : i64
      scf.yield %k, %a : i64, !llvm.ptr
    } else {
      %j = arith.subi %i, %c1 : i64
      %s, %c = func.call @find(%a, %n, %j) : (!llvm.ptr, i64, i64) -> (i64, !llvm.ptr)
      scf.yield %s, %c : i64, !llvm.ptr
    }
    return %r, %b : i64, !llvm.ptr
  }
  func.func private @sometimes(%a: !llvm.ptr, %b: !llvm.ptr, %n: i64) -> (i64, !llvm.ptr) {
    %c0 = arith.constant 0 : i64
    %zero = arith.cmpi eq, %n, %c0 : i64
    %r = scf.if %zero -> (!llvm.ptr) {
      scf.yield %a : !llvm.ptr
    } else {
      scf.yield %b : !llvm.ptr
    }
    return %n, %r : i64, !llvm.ptr
  }
  func.func private @loop(%a: !llvm.ptr, %n: i64) -> (i64, !llvm.ptr) {
    %c0 = arith.constant 0 : i64
    %c1 = arith.constant 1 : i64
    %c7 = arith.constant 7 : i64
    %r:4 = scf.while (%s = %a, %i = %n) : (!llvm.ptr, i64) -> (!llvm.ptr, i64, i64, !llvm.ptr) {
      %done = arith.cmpi eq, %i, %c0 : i64
      %p = ub.poison : !llvm.ptr
      %q = ub.poison : i64
      %next:4 = scf.if %done -> (i1, i64, i64, !llvm.ptr) {
        %false = arith.constant false
        %k = arith.addi %n, %c7 : i64
        scf.yield %false, %q, %k, %s : i1, i64, i64, !llvm.ptr
      } else {
        %true = arith.constant true
        %j = arith.subi %i, %c1 : i64
        scf.yield %true, %j, %q, %p : i1, i64, i64, !llvm.ptr
      }
      scf.condition(%next#0) %s, %next#1, %next#2, %next#3 : !llvm.ptr, i64, i64, !llvm.ptr
    } do {
    ^bb0(%s2: !llvm.ptr, %i2: i64, %v: i64, %out: !llvm.ptr):
      scf.yield %s2, %i2 : !llvm.ptr, i64
    }
    return %r#2, %r#3 : i64, !llvm.ptr
  }
  func.func private @named(%a: !llvm.ptr, %n: i64) -> (i64, !llvm.ptr) {
    return %n, %a : i64, !llvm.ptr
  }
}
