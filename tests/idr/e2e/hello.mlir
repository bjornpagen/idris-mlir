// RUN: idris-mlir-cc %s -o %t.o
// RUN: llvm-nm --undefined-only --format=just-symbols %t.o | FileCheck %s --check-prefix=EXT
// RUN: %cc %t.o -o %t
// RUN: echo -n "xé" | %t > %t.out
// RUN: FileCheck %s < %t.out
// An IO root: output through the runtime's buffer, flushed before reading
// and when main returns; input decoded as UTF-8, then bytes, then 255 at the
// end. The object needs nothing from the C library but write and read,
// and getenv, which asks at exit whether to report the cells still live.
// EXT: getenv
// EXT-NEXT: read
// EXT-NEXT: write
// EXT-NOT: {{.}}
// CHECK: hello x é
// CHECK-NEXT: -42 65535 255 1.5 1e22 +inf.0
module attributes {idr.program} {
  idr.data @Unit {
    idr.ctor @MkUnit tag 0 ()
  }
  func.func @Prog.main(%w: !idr.world) -> (!idr.data<@Unit>, !idr.world) attributes {idr.total} {
    %s = idr.constant "hello " : !idr.str
    %w1 = idr.io.put_str %s, %w
    %c, %w2 = idr.io.get_char %w1
    %w3 = idr.io.put_char %c, %w2
    %sp = arith.constant 32 : i32
    %w4 = idr.io.put_char %sp, %w3
    %d, %w5 = idr.io.get_char %w4
    %w6 = idr.io.put_char %d, %w5
    %nl = arith.constant 10 : i32
    %w7 = idr.io.put_char %nl, %w6
    %n = arith.constant -42 : i64
    %w8 = idr.io.put_int signed %n, %w7 : i64
    %w9 = idr.io.put_char %sp, %w8
    %u = arith.constant -1 : i16
    %w10 = idr.io.put_int %u, %w9 : i16
    %w11 = idr.io.put_char %sp, %w10
    %b, %w12 = idr.io.get_byte %w11
    %w13 = idr.io.put_int signed %b, %w12 : i32
    %w14 = idr.io.put_char %sp, %w13
    %x = arith.constant 1.5 : f64
    %w15 = idr.io.put_double %x, %w14
    %w16 = idr.io.put_char %sp, %w15
    %y = arith.constant 1.0e22 : f64
    %w17 = idr.io.put_double %y, %w16
    %w18 = idr.io.put_char %sp, %w17
    %inf = arith.constant 0x7FF0000000000000 : f64
    %w19 = idr.io.put_double %inf, %w18
    %w20 = idr.io.put_char %nl, %w19
    %unit = idr.constant #idr.con<@Unit::@MkUnit, []> : !idr.data<@Unit>
    return %unit, %w20 : !idr.data<@Unit>, !idr.world
  }
}
