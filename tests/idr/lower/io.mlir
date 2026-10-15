// RUN: idris-mlir-opt %s --idr-lower --idr-entry -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,entry,signature=@Prog.r:()->(),call-order=@Prog.r:[@idris_rt_io_put_str,@idris_rt_io_get_byte,@idris_rt_io_put_char,@idris_rt_io_put_int_s,@idris_rt_io_put_int_u,@idris_rt_io_put_double]' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=call-order=@__idr_main:[@Prog.r,@__idr_release_cafs,@idris_rt_main_return],returns=@__idr_main:0,calls=@main:@idris_rt_start' -o /dev/null
// RUN: FileCheck %s < %t.mlir
// Each IO op calls its runtime function, in the order the world threads
// them; the world disappears (1:0), so the IO root takes and returns
// nothing. put_int extends to 64 bits as its signedness says and picks the
// _s or _u function. An IO root is called by @__idr_main, which then
// releases what the static thunks hold and returns the status 0 after the
// runtime's end of main, which flushes the output. @main hands
// @__idr_main and the program's arguments to the runtime's entry, which
// runs it on its reserved stack; a module with no target asks the
// processor for no feature, the runtime's word 0.
// CHECK-LABEL: func.func @main(
// CHECK: %[[NONE:.*]] = llvm.mlir.constant(0 : i64) : i64
// CHECK: llvm.call @idris_rt_start(%{{.*}}, %[[NONE]], %{{.*}}, %{{.*}})
idr.program @io root(@Prog.r) stage(owned) {
  idr.func @Prog.r(%w: !idr.world) -> !idr.world {
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
