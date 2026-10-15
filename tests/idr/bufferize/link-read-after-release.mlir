// RUN: %status 1 idris-mlir-opt %s --idr-bufferize -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// A link of a linear thread (a release of a buffer a use began) must be in
// place, every time: an LArray aliases nothing, so no program reads a
// link's buffer after its release. Here the module does, which only a
// broken pass can make: bufferization reports it as the compiler's
// internal error at the release, with the read and One-Shot's own
// conflict, and never as a refusal of the program.
// CHECK: error: internal error: idr-bufferize: the linear array released here is read after its release
// CHECK-SAME: cannot avoid RaW conflict
// CHECK: note: read here
// CHECK-NOT: unsupported (
module {
  idr.func private @leak(%a: !idr.lin<tensor<?xi64>>) -> (!idr.lin<tensor<?xi64>>, i64) {
    %c0 = arith.constant 0 : index
    %seven = arith.constant 7 : i64
    %t = idr.lin.use %a : !idr.lin<tensor<?xi64>>
    %t1 = tensor.insert %seven into %t[%c0] : tensor<?xi64>
    %l = idr.lin.enter %t1 : !idr.lin<tensor<?xi64>>
    %v = tensor.extract %t1[%c0] : tensor<?xi64>
    return %l, %v : !idr.lin<tensor<?xi64>>, i64
  }
}
