// RUN: idris-mlir-opt %s --idr-bufferize -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=in-place=@go -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=in-place=@go' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %differential %s %t.mlir
// BEFORE-DAG: expected in-place: {{.*}}@go
// A recursive function over a value array, no linear thread: each call
// writes one element of the array it is given and gives the result of
// its own call back. The boundary analysis reads a function on a cycle of
// calls with the others until what each may read and write of its
// operands is settled, so @go's call of itself is known to write only the
// buffer it is given and to give back that buffer; nothing reads the
// array after the call, and no level copies it.
// Before the pass there is no buffer. The root has @go write as much of an
// array as the byte it reads says, and the program prints after the pass
// what it printed before, on every byte.
idr.program @"recursive-value" root(@root) stage(first) {
  idr.func @go(%a: tensor<?xi64>, %k: i64) -> tensor<?xi64> attributes {total} {
    %r = idr.match_lit %k : i64 -> (tensor<?xi64>) {
    case 0 {
      idr.yield %a : tensor<?xi64>
    }
    default(%d0: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %k, %one : i64
      %i = arith.index_cast %j : i64 to index
      %t = tensor.insert %k into %a[%i] : tensor<?xi64>
      %n = idr.call @go(%t, %j) : (tensor<?xi64>, i64) -> tensor<?xi64>
      idr.yield %n : tensor<?xi64>
    }
    }
    return %r : tensor<?xi64>
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
    %r = idr.call @go(%t, %k) : (tensor<?xi64>, i64) -> tensor<?xi64>
    %v = idr.call @digest(%r, %c32) : (tensor<?xi64>, index) -> i64
    %w1 = idr.io.put_sint %v, %w0 : i64
    return %w1 : !idr.world
  }
}
