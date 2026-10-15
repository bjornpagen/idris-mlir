// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@fresh -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@twoWrites -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@afterCon -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@sharedResult -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@constant -o /dev/null
// NEEDS-ACCEPTANCE: R11's analysis of released buffers (B6) and of call results (B7): each function marked to copy writes a copy, and @fresh writes in place.
// A buffer may be written in place only when nothing else holds it. A
// fresh buffer written once is (@fresh). Two writes of one empty tensor,
// which CSE made one, are not: the second writes a copy (@twoWrites). A
// buffer stored in a constructor, or returned by a callee that keeps it,
// is held elsewhere, so a write after either copies (@afterCon,
// @sharedResult), and so does a write to a constant's buffer, whose global
// lives in the program (@constant).
!Box = !idr.data<"Box", plain [@MkBox(tensor<4xi64>)]>
idr.program @aliasing root(@root) stage(first) {
  idr.func @fresh() -> tensor<4xi64> {
    %c0 = arith.constant 0 : index
    %seven = arith.constant 7 : i64
    %e = tensor.empty() : tensor<4xi64>
    %t = tensor.insert %seven into %e[%c0] : tensor<4xi64>
    return %t : tensor<4xi64>
  }
  idr.func @twoWrites() -> (tensor<4xi64>, tensor<4xi64>) {
    %c0 = arith.constant 0 : index
    %one = arith.constant 1 : i64
    %two = arith.constant 2 : i64
    %e = tensor.empty() : tensor<4xi64>
    %a = tensor.insert %one into %e[%c0] : tensor<4xi64>
    %b = tensor.insert %two into %e[%c0] : tensor<4xi64>
    return %a, %b : tensor<4xi64>, tensor<4xi64>
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
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
