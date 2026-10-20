// RUN: idris-mlir-opt %s --idr-defunctionalize > %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=labels=@both:arg0:[] -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=labels=@both:arg0:[]' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=labels=@both:arg0:[@both]' -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=labels-least -o /dev/null
// BEFORE-DAG: expected labels: @both {{.*}}
// A closure no label reaches is a value the program never has: the sum of
// @both's parameter holds no label, so an apply of it runs nowhere. A
// curried apply, whose result is applied in turn, gives a closure no label
// reaches either, and the pass converts both.
// No label reaches @both, so nothing runs it and no input could tell; the
// property did not hold before the pass, and a list naming a label fails
// after it.
idr.program @"curried-apply-poison" root(@Prog.main) stage(higher) types #idr.types<> {
  idr.func @both(%f: !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>, %x: i64, %y: i64) -> i64 {
    %g = idr.apply %f(%x) : !idr.fn<(i64) -> (!idr.fn<(i64) -> (i64)>)>
    %r = idr.apply %g(%y) : !idr.fn<(i64) -> (i64)>
    return %r : i64
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
