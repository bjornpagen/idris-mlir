// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@fill,in-place -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=in-place=@fill,in-place' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %differential %s %t.mlir
// BEFORE-DAG: expected in-place: {{.*}}@fill
// BEFORE-DAG: expected in-place:
// A linear array's thread is written in place: @fill takes the array at
// quantity one, unwraps it, writes every element and wraps it again for
// its caller, and nothing is copied, in @fill or anywhere: the root's
// fresh array is a thread's head no one reads after it, so its release
// copies nothing either. The grade is kept on the buffer.
// Before the pass there is no buffer, so in-place holds of nothing. The
// root fills an array as long as the byte it reads says and @fill writes
// part of it, and the program prints after the pass what it printed before,
// on every byte.
idr.program @"linear-thread" root(@root) stage(first) types #idr.types<> {
  idr.func @fill(%a: !idr.lin<tensor<?xi64>>, %n: index) -> !idr.lin<tensor<?xi64>> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %t = idr.lin.use %a : !idr.lin<tensor<?xi64>>
    %r = scf.for %i = %c0 to %n step %c1 iter_args(%b = %t) -> (tensor<?xi64>) {
      %x = arith.index_cast %i : index to i64
      %b1 = tensor.insert %x into %b[%i] : tensor<?xi64>
      scf.yield %b1 : tensor<?xi64>
    }
    %l = idr.lin.enter %r : !idr.lin<tensor<?xi64>>
    return %l : !idr.lin<tensor<?xi64>>
  }
  // The elements of an array, each times one more than its index, summed:
  // a number that tells apart any two arrays of small elements.
  idr.func @digest(%t: tensor<?xi64>, %n: index) -> i64 {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %zero = arith.constant 0 : i64
    %s = scf.for %i = %c0 to %n step %c1 iter_args(%acc = %zero) -> (i64) {
      %x = tensor.extract %t[%i] : tensor<?xi64>
      %i1 = arith.addi %i, %c1 : index
      %k = arith.index_cast %i1 : index to i64
      %y = arith.muli %x, %k : i64
      %acc1 = arith.addi %acc, %y : i64
      scf.yield %acc1 : i64
    }
    return %s : i64
  }
  // The program's root fills a fresh array as long as the byte it reads
  // modulo 32, plus 8, with 7s, then @fill writes the first part of it, as
  // long as the byte modulo 8 plus 1, and the root prints the digest.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c7i = arith.constant 7 : i64
    %c8i = arith.constant 8 : i64
    %c31 = arith.constant 31 : i64
    %c1i = arith.constant 1 : i64
    %len = arith.andi %b, %c31 : i64
    %len8 = arith.addi %len, %c8i : i64
    %part = arith.andi %b, %c7i : i64
    %part1 = arith.addi %part, %c1i : i64
    %n = arith.index_cast %len8 : i64 to index
    %m = arith.index_cast %part1 : i64 to index
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %e = tensor.empty(%n) : tensor<?xi64>
    %t = scf.for %i = %c0 to %n step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %a1 = tensor.insert %c7i into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %h = idr.lin.enter %t : !idr.lin<tensor<?xi64>>
    %l = idr.call @fill(%h, %m) : (!idr.lin<tensor<?xi64>>, index) -> !idr.lin<tensor<?xi64>>
    %u = idr.lin.use %l : !idr.lin<tensor<?xi64>>
    %v = idr.call @digest(%u, %n) : (tensor<?xi64>, index) -> i64
    %w1 = idr.io.put_sint %v, %w0 : i64
    return %w1 : !idr.world
  }
}
