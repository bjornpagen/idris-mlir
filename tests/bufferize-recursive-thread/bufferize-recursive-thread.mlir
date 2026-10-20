// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@go -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=in-place=@go' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %differential %s %t.mlir
// BEFORE-DAG: expected in-place: {{.*}}@go
// A recursive function threading a linear array writes it in place on
// every call: the boundary analysis reads each function on a cycle of
// calls with the others, until what each may read and write of its
// operands is settled, so @go's call of itself is known to write only
// the buffer it is given; the caller's release already made that buffer
// the thread's, and each link inside @go is in place by the analysis's
// own check.
// Before the pass there is no buffer. The root has @go write as much of an
// array as the byte it reads says, and the program prints after the pass
// what it printed before, on every byte.
idr.program @"recursive-thread" root(@root) stage(first) types #idr.types<> {
  idr.func @go(%a: !idr.lin<tensor<?xi64>>, %k: i64) -> !idr.lin<tensor<?xi64>> {
    %r = idr.match_lit %k : i64 -> (!idr.lin<tensor<?xi64>>) {
    case 0 {
      idr.yield %a : !idr.lin<tensor<?xi64>>
    }
    default(%d0: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %k, %one : i64
      %i = arith.index_cast %j : i64 to index
      %t = idr.lin.use %a : !idr.lin<tensor<?xi64>>
      %t1 = tensor.insert %k into %t[%i] : tensor<?xi64>
      %l = idr.lin.enter %t1 : !idr.lin<tensor<?xi64>>
      %n = idr.call @go(%l, %j) : (!idr.lin<tensor<?xi64>>, i64) -> !idr.lin<tensor<?xi64>>
      idr.yield %n : !idr.lin<tensor<?xi64>>
    }
    }
    return %r : !idr.lin<tensor<?xi64>>
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
  // The program's root makes an array of 32 zeros, and @go writes as
  // much of it as the byte it reads modulo 32 says; the root prints the
  // digest.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %ch, %w0 = idr.io.get_byte %w
    %b = arith.extui %ch : i32 to i64
    %c31 = arith.constant 31 : i64
    %k = arith.andi %b, %c31 : i64
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %c32 = arith.constant 32 : index
    %zero = arith.constant 0 : i64
    %e = tensor.empty(%c32) : tensor<?xi64>
    %t = scf.for %i = %c0 to %c32 step %c1 iter_args(%a = %e) -> (tensor<?xi64>) {
      %a1 = tensor.insert %zero into %a[%i] : tensor<?xi64>
      scf.yield %a1 : tensor<?xi64>
    }
    %h = idr.lin.enter %t : !idr.lin<tensor<?xi64>>
    %l = idr.call @go(%h, %k) : (!idr.lin<tensor<?xi64>>, i64) -> !idr.lin<tensor<?xi64>>
    %u = idr.lin.use %l : !idr.lin<tensor<?xi64>>
    %v = idr.call @digest(%u, %c32) : (tensor<?xi64>, index) -> i64
    %w1 = idr.io.put_sint %v, %w0 : i64
    return %w1 : !idr.world
  }
}
