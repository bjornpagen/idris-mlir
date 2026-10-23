// RUN: idris-mlir-opt %s -o /dev/null
// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=first})' -o /dev/null
// A linear array that a callee writes, passed where its buffer may not be
// written, is copied before the call, and the copy takes the array's place
// at the uses Idris proved of it, claiming what the tensor it is made of
// states: nothing of its sharing. @view fills a buffer of one word and gives
// it as a linear array through upstream's to_tensor, not writable, so its
// callers may not write it; @fill writes the array it is given at its last
// step and gives it back. @main reads a line, so no length it passes is a
// constant, views two buffers and passes each view to @fill, so
// bufferization copies each before its call, through the hook that makes a
// graded array's copy. The module verifies as written and after every pass
// to the end of the first stage, bufferization's among them, where each
// call verifies only if the copy it is given is at its parameter's grade:
// used once, claiming nothing. Each function recurses, so each stays a
// function wherever
// another is inlined into it, and @main calls each twice where no tail is
// lost, so each returns to more than one place and none becomes a join
// point of one caller.
!Linear = !idr.graded<once, counted, tensor<i64>>
idr.program @copies root(@main) stage(first) {
  idr.func @main() {
    %line = idr.io.get_line : () -> !idr.str
    %k = idr.str.length %line : (!idr.str) -> i64
    %one = arith.constant 1 : i64
    %k1 = arith.addi %k, %one : i64
    %a = idr.call @view(%k) <{tail_kind = nontail}> : (i64) -> !Linear
    %b = idr.call @view(%k1) <{tail_kind = nontail}> : (i64) -> !Linear
    %fa = idr.call @fill(%a, %k) <{tail_kind = nontail}> : (!Linear, i64) -> !Linear
    %fb = idr.call @fill(%b, %k1) <{tail_kind = nontail}> : (!Linear, i64) -> !Linear
    %pa = idr.lin.cast %fa : !Linear -> tensor<i64>
    %ea = tensor.extract %pa[] : tensor<i64>
    %pb = idr.lin.cast %fb : !Linear -> tensor<i64>
    %eb = tensor.extract %pb[] : tensor<i64>
    %sum = arith.addi %ea, %eb : i64
    %text = idr.str.show_sint %sum : (i64) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
  idr.func @view(%k: i64) -> !Linear {
    %r = idr.lit.match %k : i64 -> (!Linear) {
    case 0(%zero: i64) {
      %m = memref.alloc() : memref<i64>
      memref.store %zero, %m[] : memref<i64>
      %t = bufferization.to_tensor %m restrict : memref<i64> to tensor<i64>
      %l = idr.lin.cast %t : tensor<i64> -> !Linear
      idr.yield %l : !Linear
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.call @view(%j) <{tail_kind = tail}> : (i64) -> !Linear
      idr.yield %again : !Linear
    }
    }
    idr.return %r : !Linear
  }
  idr.func @fill(%a: !Linear, %k: i64) -> !Linear {
    %r = idr.lit.match %k : i64 -> (!Linear) {
    case 0(%zero: i64) {
      %plain = idr.lin.cast %a : !Linear -> tensor<i64>
      %w = tensor.insert %zero into %plain[] : tensor<i64>
      %written = idr.lin.cast %w : tensor<i64> -> !Linear
      idr.yield %written : !Linear
    }
    default(%d: i64) {
      %one = arith.constant 1 : i64
      %j = arith.subi %d, %one : i64
      %again = idr.call @fill(%a, %j) <{tail_kind = tail}> : (!Linear, i64) -> !Linear
      idr.yield %again : !Linear
    }
    }
    idr.return %r : !Linear
  }
}
