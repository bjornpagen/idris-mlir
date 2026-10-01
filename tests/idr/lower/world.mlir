// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// A forged world has no runtime form, like every world: what is left of a
// chain on one is the IO it did.
// CHECK-LABEL: func.func private @f(
// CHECK-NOT: world
// CHECK: llvm.call @idris_rt_io_put_char
// CHECK-NOT: world
// CHECK: return
module attributes {idr.program, idr.stage = "owned"} {
  func.func @root(%w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    func.call @f(%c) : (i32) -> ()
    return %w : !idr.world
  }
  func.func private @f(%c: i32) {
    %w = idr.world.new
    %w1 = idr.io.put_char %c, %w
    return
  }
}
