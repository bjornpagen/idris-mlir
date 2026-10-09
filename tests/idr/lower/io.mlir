// RUN: idris-mlir-opt %s --idr-lower --idr-entry | FileCheck %s
// Each IO op calls its runtime function; the world disappears (1:0). put_int
// extends to 64 bits as its signedness says and picks the _s or _u function.
// An IO root is called by @__idr_main, which then releases what the static
// thunks hold and returns the status 0 after the runtime's end of main,
// which flushes the output. @main hands @__idr_main and the program's
// arguments to the runtime's entry, which runs it on its reserved stack;
// a module with no target asks the processor for no feature.
// CHECK-LABEL: func.func private @Prog.r()
// CHECK: llvm.call @idris_rt_io_put_str(%{{.*}}) : (!llvm.ptr) -> ()
// CHECK: %[[C:.*]] = llvm.call @idris_rt_io_get_byte() : () -> i32
// CHECK: llvm.call @idris_rt_io_put_char(%[[C]]) : (i32) -> ()
// CHECK: %[[S:.*]] = arith.extsi %{{.*}} : i8 to i64
// CHECK: llvm.call @idris_rt_io_put_int_s(%[[S]]) : (i64) -> ()
// CHECK: %[[U:.*]] = arith.extui %{{.*}} : i16 to i64
// CHECK: llvm.call @idris_rt_io_put_int_u(%[[U]]) : (i64) -> ()
// CHECK: llvm.call @idris_rt_io_put_double(%{{.*}}) : (f64) -> ()
// CHECK: return
// CHECK-LABEL: func.func private @__idr_main() -> i64
// CHECK: call @Prog.r() : () -> ()
// CHECK: %[[Z:.*]] = llvm.mlir.constant(0 : i64) : i64
// CHECK: call @__idr_release_cafs() : () -> ()
// CHECK: llvm.call @idris_rt_main_return() : () -> ()
// CHECK: return %[[Z]] : i64
// CHECK-LABEL: func.func @main(
// CHECK: %[[F:.*]] = constant @__idr_main : () -> i64
// CHECK: %[[P:.*]] = builtin.unrealized_conversion_cast %[[F]]
// CHECK: %[[NONE:.*]] = llvm.mlir.constant(0 : i64) : i64
// CHECK: %[[R:.*]] = llvm.call @idris_rt_start(%[[P]], %[[NONE]], %{{.*}}, %{{.*}})
// CHECK: return %[[R]] : i32
module attributes {idr.program} {
  func.func @Prog.r(%w: !idr.world) -> !idr.world {
    %s = idr.constant "h\C3\A9llo\0A" : !idr.str
    %w1 = idr.io.put_str %s, %w
    %c, %w2 = idr.io.get_byte %w1
    %w3 = idr.io.put_char %c, %w2
    %n = arith.constant -42 : i8
    %w4 = idr.io.put_int signed %n, %w3 : i8
    %u = arith.constant -1 : i16
    %w5 = idr.io.put_int %u, %w4 : i16
    %d = arith.constant 1.5 : f64
    %w6 = idr.io.put_double %d, %w5
    return %w6 : !idr.world
  }
}
