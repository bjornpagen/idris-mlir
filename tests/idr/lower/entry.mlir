// RUN: idris-mlir-opt %s -split-input-file --idr-lower --idr-entry > %t.mlir
// RUN: FileCheck %s --check-prefix=MAIN < %t.mlir
// RUN: FileCheck %s --check-prefix=BODY < %t.mlir
// RUN: FileCheck %s --check-prefix=ROOT --implicit-check-not='func.func @Prog' < %t.mlir
// idr-entry makes the lowered root the program's entry. @main takes the
// program's arguments, the count and the vector, and hands them to the
// runtime's entry with @__idr_main, whose status it returns. @__idr_main
// calls the root, which is no longer public, then releases what the static
// thunks hold, then ends main in the runtime. The root's lowered type is
// its kind: `() -> i64` gives the status, and an IO root, `() -> ()` once
// its world is gone, gives 0.
// MAIN-LABEL: func.func @main(
// MAIN-SAME: %[[ARGC:[^:]*]]: i32, %[[ARGV:[^:]*]]: !llvm.ptr) -> i32
// MAIN: %[[S:.*]] = llvm.call @idris_rt_start(%{{.*}}, %{{.*}}, %[[ARGC]], %[[ARGV]]) : (!llvm.ptr, i64, i32, !llvm.ptr) -> i32
// MAIN: return %[[S]] : i32
// MAIN-LABEL: func.func @main(
// MAIN-SAME: %[[ARGC:[^:]*]]: i32, %[[ARGV:[^:]*]]: !llvm.ptr) -> i32
// MAIN: %[[S:.*]] = llvm.call @idris_rt_start(%{{.*}}, %{{.*}}, %[[ARGC]], %[[ARGV]]) : (!llvm.ptr, i64, i32, !llvm.ptr) -> i32
// MAIN: return %[[S]] : i32
// BODY-LABEL: func.func private @__idr_main() -> i64
// BODY-NEXT: %[[S:.*]] = call @Prog.main() : () -> i64
// BODY-NEXT: call @__idr_release_cafs() : () -> ()
// BODY-NEXT: llvm.call @idris_rt_main_return() : () -> ()
// BODY-NEXT: return %[[S]] : i64
// BODY-LABEL: func.func private @__idr_main() -> i64
// BODY-NEXT: call @Prog.main() : () -> ()
// BODY-NEXT: %[[Z:.*]] = llvm.mlir.constant(0 : i64) : i64
// BODY-NEXT: call @__idr_release_cafs() : () -> ()
// BODY-NEXT: llvm.call @idris_rt_main_return() : () -> ()
// BODY-NEXT: return %[[Z]] : i64
// ROOT: func.func private @Prog.main() -> i64
// ROOT: func.func private @Prog.main() {
module attributes {idr.program} {
  func.func @Prog.main() -> i64 {
    %c = arith.constant 3 : i64
    return %c : i64
  }
}

// -----

module attributes {idr.program} {
  func.func @Prog.main(%w: !idr.world) -> !idr.world {
    %s = idr.constant "hi\0A" : !idr.str
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
}
