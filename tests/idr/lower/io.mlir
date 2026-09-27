// RUN: idris-mlir-opt %s --idr-check-input --idr-entry --idr-lower | FileCheck %s
// rule: LOW-IO-1, LOW-IO-2, LOW-IO-3, LOW-STR-1, LOW-CHAR-1, LOW-ENTRY-1, LOW-EXT-1
// CHECK: llvm.mlir.global internal constant @__idr_str_0("h\C3\A9llo\0A")
// CHECK-LABEL: func.func private @Prog.r() -> i64
// CHECK: %[[P:.*]] = llvm.mlir.addressof @__idr_str_0 : !llvm.ptr
// CHECK: call @__idr_put_bytes(%[[P]], %{{.*}})
// CHECK: %[[C:.*]] = call @__idr_get_char() : () -> i32
// CHECK: call @__idr_put_char(%[[C]])
// CHECK: call @__idr_put_int_s(
// CHECK: call @__idr_exit(
// CHECK-DAG: llvm.func @write(i32, !llvm.ptr, i64) -> i64
// CHECK-DAG: llvm.func @read(i32, !llvm.ptr, i64) -> i64
// CHECK-DAG: llvm.func @_exit(i32)
// CHECK-LABEL: func.func @main() -> i32
// CHECK: call @Prog.r()
// CHECK: call @__idr_flush()
module attributes {idr.version = 1 : i64, idr.entry = @Prog.r, idr.entry_kind = "io"} {
  func.func private @Prog.r(%w: !idr.world {idr.quantity = "1"}) -> i64 {
    %s = idr.str.lit "h\C3\A9llo\0A" : !idr.str
    %w1 = idr.io.put_str %s, %w
    %c, %w2 = idr.io.get_char %w1
    %w3 = idr.io.put_char %c, %w2
    %n = arith.constant -42 : i64
    %w4 = idr.io.put_int signed %n, %w3 : i64
    %e = arith.constant 3 : i64
    %w5 = idr.io.exit %e, %w4
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
