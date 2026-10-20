// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=moves-out=@pop,in-place=@pop -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=moves-out=@pop,in-place=@pop' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %differential %s %t.mlir
// BEFORE-DAG: expected moves-out: {{.*}}@pop
// BEFORE-DAG: expected in-place: {{.*}}@pop
// A vector's pop on its buffer: the last element is read and the fill is
// written over its place. The element holds a reference, so a read of it
// would take a reference of its own and the write would release the
// buffer's; read just before the write, and used by nothing between, it
// moves out of the buffer instead, with the buffer's reference, and the
// fill moves in over the place it left. The buffer is the thread's own, so
// nothing is copied.
// Neither held before the pass. The root pops the last of an array of
// records as long as the byte it reads says, and the program prints after
// the pass what it printed before, on every byte: the popped record, and
// the fill in its place.
!R = !idr.data<"R">
#types = #idr.types<
  "R" = plain [@MkR(i64)]
>
idr.program @"pop-box" root(@root) stage(first) types #types {
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
  // The program's root fills an array as long as the byte it reads modulo
  // 8 plus 1 with records of their index plus the byte, pops the last with
  // a record of 1000 in its place, and prints the popped record's field
  // and the sum of what the array holds after.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %y = arith.extui %ch : i32 to i64
    %c7 = arith.constant 7 : i64
    %c1i = arith.constant 1 : i64
    %k = arith.andi %y, %c7 : i64
    %k1 = arith.addi %k, %c1i : i64
    %n = arith.index_cast %k1 : i64 to index
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %thousand = arith.constant 1000 : i64
    %fill = idr.con !idr.box<!R> @MkR(%thousand : i64)
    %e = tensor.empty(%n) : tensor<?x!idr.box<!R>>
    %t = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?x!idr.box<!R>>) {
      %ii = arith.index_cast %i : index to i64
      %v = arith.addi %ii, %y : i64
      %r = idr.con !idr.box<!R> @MkR(%v : i64)
      %a1 = tensor.insert %r into %a[%i] : tensor<?x!idr.box<!R>>
      scf.yield %a1 : tensor<?x!idr.box<!R>>
    }
    %h = idr.lin.enter %t : !idr.lin<tensor<?x!idr.box<!R>>>
    %x, %l = idr.call @pop(%h, %n, %fill) : (!idr.lin<tensor<?x!idr.box<!R>>>, index, !idr.box<!R>) -> (!idr.box<!R>, !idr.lin<tensor<?x!idr.box<!R>>>)
    %v = idr.field %x : !idr.box<!R> @MkR[0] -> i64
    %w1 = idr.io.put_sint %v, %w0 : i64
    %u = idr.lin.use %l : !idr.lin<tensor<?x!idr.box<!R>>>
    %zero = arith.constant 0 : i64
    %s = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %zero) -> (i64) {
      %r = tensor.extract %u[%i] : tensor<?x!idr.box<!R>>
      %f = idr.field %r : !idr.box<!R> @MkR[0] -> i64
      %acc1 = arith.addi %acc, %f : i64
      scf.yield %acc1 : i64
    }
    %w2 = idr.io.put_sint %s, %w1 : i64
    return %w2 : !idr.world
  }
}
