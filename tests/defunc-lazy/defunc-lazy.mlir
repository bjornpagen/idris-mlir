// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=calls=@Main.main:@now,calls=@Main.main:@later' -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=calls=@Main.main:@now,calls=@Main.main:@later' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// BEFORE-DAG: expected calls: @Main.main {{.*}}@now
// BEFORE-DAG: expected calls: @Main.main {{.*}}@later
// A Lazy value picked at runtime, stored in a field and forced later: the
// suspensions become constructors of a sum, the field's type follows, and
// the apply is a match that calls the suspended function.
// The program means after the pass what it meant before it, on every input
// (the differential), and no property here held before the pass.
!Box = !idr.data<"Box", plain [@MkBox(!idr.fn<() -> (i64)>)]>
idr.program @lazy root(@Main.main) stage(higher) {
  idr.func @now() -> i64 attributes {total} {
    %c = arith.constant 7 : i64
    return %c : i64
  }
  idr.func @later(%x: i64) -> i64 attributes {total} {
    %y = arith.muli %x, %x : i64
    return %y : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %n = arith.extui %c : i32 to i64
    %s = idr.match_lit %n : i64 -> (!idr.fn<() -> (i64)>) {
    case 65 {
      %a = idr.closure @now() : () -> !idr.fn<() -> (i64)>
      idr.yield %a : !idr.fn<() -> (i64)>
    }
    default(%d: i64) {
      %b = idr.closure @later(%n) : (i64) -> !idr.fn<() -> (i64)>
      idr.yield %b : !idr.fn<() -> (i64)>
    }
    }
    %box = idr.con !Box @MkBox(%s : !idr.fn<() -> (i64)>)
    %l = idr.field %box : !Box @MkBox[0] -> !idr.fn<() -> (i64)>
    %r = idr.apply %l() : !idr.fn<() -> (i64)>
    %w2 = idr.io.put_sint %r, %w1 : i64
    return %w2 : !idr.world
  }
}
