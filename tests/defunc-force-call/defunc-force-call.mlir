// RUN: idris-mlir-opt %s --idr-defunctionalize -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=forces-nothing=@user,forces-nothing=@Main.main,reaches=@user:@label -o /dev/null
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=forces-nothing=@user,forces-nothing=@Main.main,reaches=@user:@label -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: idris-mlir-opt %s --idr-expect=holds=labels-least -o /dev/null
// BEFORE-DAG: expected forces-nothing: {{.*}} in @user
// BEFORE-DAG: expected forces-nothing: {{.*}} in @Main.main
// BEFORE-DAG: expected reaches: @user {{.*}}@label
// A force is a call: idr-defunctionalize makes each memo sum one dispatch
// function, which a force of a cell of the sum becomes a call of, and
// which calls the function of the label it finds in the cell. So no force
// is left, and the call graph reaches the label's code from @user, which
// only forces a cell of it; the program then prints what it printed before
// the pass on every byte. None of this held before the pass. That every
// call names its callee, and that @Main.main reaches @label, held before the
// pass as well (@Main.main names @label in its suspension), so neither is
// checked here.
idr.program @"force-call" root(@Main.main) stage(higher) types #idr.types<> {
  idr.func @label(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @user(%t: !idr.lazy<i64>) -> i64 attributes {total} {
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @Main.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %t = idr.suspend @label(%x) : (i64) -> !idr.lazy<i64>
    %v = idr.call @user(%t) : (!idr.lazy<i64>) -> i64
    %u = idr.force %t : !idr.lazy<i64> -> i64
    %s = arith.addi %v, %u : i64
    %w2 = idr.io.put_sint %s, %w1 : i64
    return %w2 : !idr.world
  }
}
