// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// idr.crash calls the runtime's crash, which does not return, with its
// message and location; a function that never returns returns poison
// after it, which is never reached, and in a match region (now scf) the
// region yields a value that is never used: poison, or for a reference an
// empty one. A division
// by what may be zero crashes first when it is.
// CHECK-DAG: llvm.func @idris_rt_crash(!llvm.ptr, i64) attributes {passthrough = ["noreturn"]}
// CHECK-DAG: llvm.mlir.constant("idris-mlir: unhandled input for Main.name at Main.idr:3:1\0A")
// CHECK-DAG: llvm.mlir.constant("idris-mlir: division by zero at Main.idr:9:5\0A")
// CHECK-LABEL: func.func private @Main.name(
// CHECK: scf.index_switch
// CHECK: default {
// CHECK: llvm.call @idris_rt_crash(%{{.*}}, %{{.*}}) {{.*}}: (!llvm.ptr, i64) -> ()
// CHECK-NEXT: %[[P:.*]] = llvm.mlir.zero : !llvm.ptr
// CHECK-NEXT: scf.yield %[[P]] : !llvm.ptr
// CHECK-LABEL: func.func private @Main.never(
// CHECK: llvm.call @idris_rt_crash
// CHECK: return
// CHECK-LABEL: func.func private @Main.half(
// CHECK-SAME: %{{[^:]+}}: i64, %[[B:[^:]+]]: i64
// CHECK: %[[Z:.*]] = arith.cmpi eq, %[[B]], %{{.*}} : i64
// CHECK: scf.if %[[Z]] {
// CHECK: llvm.call @idris_rt_crash
// CHECK: arith.divsi
module attributes {idr.program} {
  func.func private @Main.name(%n: i64) -> !idr.str {
    %r = idr.match_lit %n : i64 -> (!idr.str) {
    case 1 {
      %s = idr.constant "one" : !idr.str
      idr.yield %s : !idr.str
    }
    default {
      idr.crash "unhandled input for Main.name" loc("Main.idr":3:1)
      ub.unreachable
    }
    }
    return %r : !idr.str
  }
  func.func private @Main.never(%n: i64) -> i64 {
    idr.crash "unhandled input for Main.never" loc("Main.idr":6:1)
    %never = ub.poison : i64
    return %never : i64
  }
  func.func private @Main.half(%a: i64, %b: i64) -> i64 {
    %q = idr.div signed %a, %b : i64 loc("Main.idr":9:5)
    return %q : i64
  }
  func.func @Main.main() -> i64 {
    %one = arith.constant 1 : i64
    %s = func.call @Main.name(%one) : (i64) -> !idr.str
    %n = func.call @Main.never(%one) : (i64) -> i64
    %h = func.call @Main.half(%n, %one) : (i64, i64) -> i64
    return %h : i64
  }
}
