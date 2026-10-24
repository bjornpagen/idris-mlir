// A graded array that One-Shot copies at the cast that makes it, where the
// copy is the cast's result and not an operand: @main views a buffer of one
// word as a builtin tensor that is not writable, casts the tensor to a linear
// array, which @fill writes, and reads the tensor after the calls. In place,
// @fill would write the buffer the tensor views, so the cast's operand
// bufferizes out of place; the cast writes nothing and its result is its
// operand's one alias, so One-Shot copies the result, through the hook that
// makes a graded array's copy. The hook reads the array through a cast of its
// own (the array at a builtin tensor's grade, which upstream's copy takes) and
// gives the copy at the array's uses. The module verifies after every pass to
// the end of the first stage, bufferization's among them, only if that cast
// still reads the array and only @fill's call reads the copy: given the copy,
// the hook's cast would read the value it defines. @main reads a line, so no
// length it passes is a constant. @fill recurses, so it stays a function
// wherever another is inlined into it, and @main calls it twice where no tail
// is lost, so it returns to more than one place and is no join point of one
// caller.
!Linear = !idr.graded<once, counted, tensor<i64>>
idr.program @copied_result root(@main) stage(first) {
  idr.func @main() {
    %line = idr.io.get_line : () -> !idr.str
    %k = idr.str.length %line : (!idr.str) -> i64
    %one = arith.constant 1 : i64
    %k1 = arith.addi %k, %one : i64
    %m = memref.alloc() : memref<i64>
    memref.store %k, %m[] : memref<i64>
    %t = bufferization.to_tensor %m restrict : memref<i64> to tensor<i64>
    %a = idr.lin.cast %t : tensor<i64> -> !Linear
    %fa = idr.call @fill(%a, %k) <{tail_kind = nontail}> : (!Linear, i64) -> !Linear
    %fb = idr.call @fill(%fa, %k1) <{tail_kind = nontail}> : (!Linear, i64) -> !Linear
    %pb = idr.lin.cast %fb : !Linear -> tensor<i64>
    %eb = tensor.extract %pb[] : tensor<i64>
    %et = tensor.extract %t[] : tensor<i64>
    %sum = arith.addi %eb, %et : i64
    %text = idr.str.show_sint %sum : (i64) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
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
