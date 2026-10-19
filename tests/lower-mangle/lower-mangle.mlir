// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=linker-names,lowered -o /dev/null
// A function's symbol is its Idris name with its instance's arguments,
// which may hold any character; from idr-lower on it is the name LLVM and
// the linker take, so phase 0 writes every character outside letters,
// digits, `_` and `.` as `$`, its code point, `$`: the function and its
// calls alike, so every symbol the program defines is in that alphabet.
// Static data is named in it already and keeps its names. The encoding is
// the names the linker sees. So each call reaches its function: the
// program, lowered, linked and run, prints 3x + 1 of the byte x it reads,
// through @"Main.pair[...]", @"Main.show[...]", @"Main.café" and
// @"Main.go'", as the program as written and the reference at the end
// (REF), one function, do (%differential, on 0, 255 and the end of input).
// STDIN: \0000
// STDIN: \0377
// STDIN:
idr.program @mangle root(@Prog.main) stage(owned) {
  idr.func @"Main.show[Prelude.Types.Nat]"(%n: i64) -> i64 attributes {total} {
    %r = arith.addi %n, %n : i64
    return %r : i64
  }
  idr.func @"Main.pair[Prelude.Types.Nat, Prelude.Types.Nat]"(%a: i64, %b: i64) -> i64 attributes {total} {
    %s = idr.call @"Main.show[Prelude.Types.Nat]"(%a) : (i64) -> i64
    %r = arith.addi %s, %b : i64
    return %r : i64
  }
  idr.func @"Main.go'"(%x: i64) -> i64 attributes {total} {
    %one = arith.constant 1 : i64
    %r = arith.addi %x, %one : i64
    return %r : i64
  }
  idr.func @"Main.café"(%x: i64) -> i64 {
    %v = idr.call @"Main.go'"(%x) : (i64) -> i64
    return %v : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %p = idr.call @"Main.pair[Prelude.Types.Nat, Prelude.Types.Nat]"(%x, %x) : (i64, i64) -> i64
    %v = idr.call @"Main.café"(%p) : (i64) -> i64
    %w2 = idr.io.put_sint %v, %w1 : i64
    return %w2 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %x = arith.extui %c : i32 to i64
// REF:     %three = arith.constant 3 : i64
// REF:     %one = arith.constant 1 : i64
// REF:     %t = arith.muli %x, %three : i64
// REF:     %v = arith.addi %t, %one : i64
// REF:     %w2 = idr.io.put_sint %v, %w1 : i64
// REF:     return %w2 : !idr.world
// REF:   }
// REF: }
