// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@fresh -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@afterCon,in-place=@sharedResult,in-place=@constant -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: %differential %s %t.mlir
// A buffer may be written in place only when nothing else holds it. A
// fresh buffer written once is (@fresh). A buffer stored in a
// constructor, or returned by a callee that keeps it, is held elsewhere,
// so a write after either copies (@afterCon, @sharedResult), and so does
// a write to a constant's buffer, whose global lives in the program
// (@constant).
// CHECK-DAG: expected in-place: memref.copy {{.*}} in @afterCon
// CHECK-DAG: expected in-place: memref.copy {{.*}} in @sharedResult
// CHECK-DAG: expected in-place: memref.copy {{.*}} in @constant
// The root runs every function on an array made from the byte it reads, and
// the program prints after the pass what it printed before, on every byte:
// each copy keeps what the box beside it holds as it was.
!Box = !idr.data<"Box", plain [@MkBox(tensor<4xi64>)]>
idr.program @aliasing root(@root) stage(first) {
  idr.func @fresh() -> tensor<4xi64> {
    %c0 = arith.constant 0 : index
    %seven = arith.constant 7 : i64
    %e = tensor.empty() : tensor<4xi64>
    %t = tensor.insert %seven into %e[%c0] : tensor<4xi64>
    return %t : tensor<4xi64>
  }
  idr.func @afterCon(%t: tensor<4xi64>) -> (!Box, tensor<4xi64>) {
    %c0 = arith.constant 0 : index
    %one = arith.constant 1 : i64
    %b = idr.con !Box @MkBox(%t : tensor<4xi64>)
    %u = tensor.insert %one into %t[%c0] : tensor<4xi64>
    return %b, %u : !Box, tensor<4xi64>
  }
  idr.func @keeps(%b: !Box) -> tensor<4xi64> attributes {total} {
    %t = idr.field %b : !Box @MkBox[0] -> tensor<4xi64>
    return %t : tensor<4xi64>
  }
  idr.func @sharedResult(%b: !Box) -> (tensor<4xi64>, !Box) {
    %c0 = arith.constant 0 : index
    %one = arith.constant 1 : i64
    %t = idr.call @keeps(%b) : (!Box) -> tensor<4xi64>
    %u = tensor.insert %one into %t[%c0] : tensor<4xi64>
    return %u, %b : tensor<4xi64>, !Box
  }
  idr.func @constant() -> tensor<4xi64> {
    %c0 = arith.constant 0 : index
    %one = arith.constant 1 : i64
    %k = arith.constant dense<[1, 2, 3, 4]> : tensor<4xi64>
    %u = tensor.insert %one into %k[%c0] : tensor<4xi64>
    return %u : tensor<4xi64>
  }
  idr.func @put_at(%t: tensor<4xi64>, %i: index, %w: !idr.world) -> !idr.world {
    %x = tensor.extract %t[%i] : tensor<4xi64>
    %w1 = idr.io.put_sint %x, %w : i64
    %sp = arith.constant 32 : i32
    %w2 = idr.io.put_char %sp, %w1
    return %w2 : !idr.world
  }
  // The program's root runs every function above on an array made from
  // the byte it reads, and prints what each written array holds and what
  // the box beside it still holds, which the write did not touch.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %x = arith.extui %ch : i32 to i64
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %i1 = arith.constant 1 : i64
    %x1 = arith.addi %x, %i1 : i64
    %x2 = arith.addi %x1, %i1 : i64
    %x3 = arith.addi %x2, %i1 : i64
    %t = tensor.from_elements %x, %x1, %x2, %x3 : tensor<4xi64>
    %f = idr.call @fresh() : () -> tensor<4xi64>
    %w1 = idr.call @put_at(%f, %c0, %w0) : (tensor<4xi64>, index, !idr.world) -> !idr.world
    %b, %u = idr.call @afterCon(%t) : (tensor<4xi64>) -> (!Box, tensor<4xi64>)
    %w2 = idr.call @put_at(%u, %c0, %w1) : (tensor<4xi64>, index, !idr.world) -> !idr.world
    %w3 = idr.call @put_at(%u, %c1, %w2) : (tensor<4xi64>, index, !idr.world) -> !idr.world
    %held = idr.call @keeps(%b) : (!Box) -> tensor<4xi64>
    %w4 = idr.call @put_at(%held, %c0, %w3) : (tensor<4xi64>, index, !idr.world) -> !idr.world
    %v, %b2 = idr.call @sharedResult(%b) : (!Box) -> (tensor<4xi64>, !Box)
    %w5 = idr.call @put_at(%v, %c0, %w4) : (tensor<4xi64>, index, !idr.world) -> !idr.world
    %held2 = idr.call @keeps(%b2) : (!Box) -> tensor<4xi64>
    %w6 = idr.call @put_at(%held2, %c0, %w5) : (tensor<4xi64>, index, !idr.world) -> !idr.world
    %k = idr.call @constant() : () -> tensor<4xi64>
    %w7 = idr.call @put_at(%k, %c0, %w6) : (tensor<4xi64>, index, !idr.world) -> !idr.world
    %w8 = idr.call @put_at(%k, %c1, %w7) : (tensor<4xi64>, index, !idr.world) -> !idr.world
    %t0 = idr.call @put_at(%t, %c0, %w8) : (tensor<4xi64>, index, !idr.world) -> !idr.world
    return %t0 : !idr.world
  }
}
