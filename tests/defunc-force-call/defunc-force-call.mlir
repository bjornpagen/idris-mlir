// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-expect=holds=forces-nothing=@user,forces-nothing=@main,direct-calls,reaches=@user:@label,reaches=@main:@label -o /dev/null
// A force is a call: idr-defunctionalize makes each memo sum one dispatch
// function, which a force of a cell of the sum becomes a call of, and
// which calls the function of the label it finds in the cell. So no force
// is left, every call names its callee, and the call graph reaches the
// label's code from every function that forces a cell of it. The program
// is then at the first stage.
idr.program @"force-call" root(@main) stage(higher) {
  idr.func @label(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  idr.func @user(%t: !idr.lazy<i64>) -> i64 attributes {total} {
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @main(%w: !idr.world) -> !idr.world {
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
