// RUN: idris-mlir-cc %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: echo -n "xé" | %t > %t.out
// RUN: FileCheck %s < %t.out
// rule: LOW-IO-2, SEM-IO-2, SEM-IO-3
// CHECK: hello x é
module attributes {idr.version = 1 : i64, idr.entry = @Prog.main, idr.entry_kind = "io"} {
  func.func private @Prog.main(%w: !idr.world {idr.quantity = "1"}) -> i64 attributes {idr.name = "main"} {
    %s = idr.str.lit "hello " : !idr.str
    %w1 = idr.io.put_str %s, %w
    %c, %w2 = idr.io.get_char %w1
    %w3 = idr.io.put_char %c, %w2
    %sp = arith.constant 32 : i32
    %w4 = idr.io.put_char %sp, %w3
    %d, %w5 = idr.io.get_char %w4
    %w6 = idr.io.put_char %d, %w5
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
