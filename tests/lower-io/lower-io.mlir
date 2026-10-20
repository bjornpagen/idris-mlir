// RUN: idris-mlir-opt %s --idr-lower -o %t.lowered.mlir
// RUN: %differential %s %t.lowered.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.lowered.mlir
// RUN: idris-mlir-opt %t.lowered.mlir --idr-entry -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,entry,signature=@Prog.r:()->(),call-order=@Prog.r:[@idris_rt_io_put_str,@idris_rt_io_get_byte,@idris_rt_io_put_char,@idris_rt_io_put_int_s,@idris_rt_io_put_int_u,@idris_rt_io_put_double]' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=call-order=@__idr$entry$body:[@Prog.r,@idris_rt_main_return],returns=@__idr$entry$body:0,calls=@main:@idris_rt_start' -o /dev/null
// Each IO op calls its runtime function, in the order the world threads
// them; the world disappears (1:0), so the IO root takes and returns
// nothing. put_int extends to 64 bits as its signedness says and picks the
// _s or _u function. An IO root is called by @__idr$entry$body, which then
// returns the status 0 after the runtime's end of main, which flushes the
// output. @main hands
// @__idr$entry$body and the program's arguments to the runtime's entry, which
// runs it on its reserved stack.
// Each runs, in that order, as its type says: the program, lowered and as
// written, prints héllo, the character of the byte it reads, -42 and 65535
// (the Int8 and the Bits16 of all ones) and 1.5, as the reference at the
// end (REF) writes them a character and an Int at a time (%differential,
// on the bytes 0, 65, 127, 128, 255 and the end of input, which reads as
// 255: a code point of one byte and of two).
// STDIN: \0000
// STDIN: A
// STDIN: \0177
// STDIN: \0200
// STDIN: \0377
// STDIN:
idr.program @io root(@Prog.r) stage(owned) types #idr.types<> {
  idr.func @Prog.r(%w: !idr.world) -> !idr.world {
    %s = idr.constant !idr.str "h\C3\A9llo\0A"
    %w1 = idr.io.put_str %s, %w
    %c, %w2 = idr.io.get_byte %w1
    %w3 = idr.io.put_char %c, %w2
    %n = arith.constant -42 : i8
    %w4 = idr.io.put_sint %n, %w3 : i8
    %u = arith.constant -1 : i16
    %w5 = idr.io.put_uint %u, %w4 : i16
    %d = arith.constant 1.5 : f64
    %w6 = idr.io.put_double %d, %w5
    return %w6 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.r) stage(higher) types #idr.types<> {
// REF:   idr.func @Prog.r(%w: !idr.world) -> !idr.world {
// REF:     %h = arith.constant 104 : i32
// REF:     %e = arith.constant 233 : i32
// REF:     %l = arith.constant 108 : i32
// REF:     %o = arith.constant 111 : i32
// REF:     %nl = arith.constant 10 : i32
// REF:     %w1 = idr.io.put_char %h, %w
// REF:     %w2 = idr.io.put_char %e, %w1
// REF:     %w3 = idr.io.put_char %l, %w2
// REF:     %w4 = idr.io.put_char %l, %w3
// REF:     %w5 = idr.io.put_char %o, %w4
// REF:     %w6 = idr.io.put_char %nl, %w5
// REF:     %c, %w7 = idr.io.get_byte %w6
// REF:     %w8 = idr.io.put_char %c, %w7
// REF:     %n = arith.constant -42 : i64
// REF:     %w9 = idr.io.put_sint %n, %w8 : i64
// REF:     %u = arith.constant 65535 : i64
// REF:     %w10 = idr.io.put_sint %u, %w9 : i64
// REF:     %d = arith.constant 1.5 : f64
// REF:     %w11 = idr.io.put_double %d, %w10
// REF:     return %w11 : !idr.world
// REF:   }
// REF: }
