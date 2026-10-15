// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=moves-out=@pop,in-place=@pop -o /dev/null
// NEEDS-ACCEPTANCE: that a pop's read of its last element and the write of the fill behind it become one idr.element.update on the vector's buffer, written in place.
// A vector's pop on its buffer: the last element is read and the fill is
// written over its place. The element holds a reference, so a read of it
// would take a reference of its own and the write would release the
// buffer's; read just before the write, and used by nothing between, it
// moves out of the buffer instead, with the buffer's reference, and the
// fill moves in over the place it left. The buffer is the thread's own, so
// nothing is copied.
!R = !idr.data<"R", plain [@MkR(i64)]>
idr.program @"pop-box" root(@root) stage(first) {
  idr.func @pop(%a: !idr.lin<tensor<?x!idr.box<!R>>>, %size: index, %fill: !idr.box<!R>)
      -> (!idr.box<!R>, !idr.lin<tensor<?x!idr.box<!R>>>) {
    %c1 = arith.constant 1 : index
    %last = arith.subi %size, %c1 : index
    %t = idr.lin.use %a : !idr.lin<tensor<?x!idr.box<!R>>>
    %x = tensor.extract %t[%last] : tensor<?x!idr.box<!R>>
    %t1 = tensor.insert %fill into %t[%last] : tensor<?x!idr.box<!R>>
    %l = idr.lin.enter %t1 : !idr.lin<tensor<?x!idr.box<!R>>>
    return %x, %l : !idr.box<!R>, !idr.lin<tensor<?x!idr.box<!R>>>
  }
  idr.func @root() -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c4 = arith.constant 4 : index
    %seven = arith.constant 7 : i64
    %b = idr.con !idr.box<!R> @MkR(%seven : i64)
    %e = tensor.empty(%c4) : tensor<?x!idr.box<!R>>
    %t = scf.for %i = %c0 to %c4 step %c1 iter_args(%a = %e) -> (tensor<?x!idr.box<!R>>) {
      %a1 = tensor.insert %b into %a[%i] : tensor<?x!idr.box<!R>>
      scf.yield %a1 : tensor<?x!idr.box<!R>>
    }
    %h = idr.lin.enter %t : !idr.lin<tensor<?x!idr.box<!R>>>
    %x, %l = idr.call @pop(%h, %c4, %b) : (!idr.lin<tensor<?x!idr.box<!R>>>, index, !idr.box<!R>) -> (!idr.box<!R>, !idr.lin<tensor<?x!idr.box<!R>>>)
    %v = idr.field %x : !idr.box<!R> @MkR[0] -> i64
    %u = idr.lin.use %l : !idr.lin<tensor<?x!idr.box<!R>>>
    return %v : i64
  }
}
