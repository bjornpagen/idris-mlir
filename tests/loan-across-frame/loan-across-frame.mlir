// RUN: idris-mlir-opt %s --pass-pipeline='builtin.module(idr-pipeline{from=first to=graded},idr-expect{holds=counts-nothing=@f})' -o /dev/null
// A loan changes no count, even when a view of the buffer it lends is read on
// both sides of a call that runs on a frame. @f reads its buffer through a
// view made before its first call of @g, on its own cycle, and reads the view
// again after it; it reads the buffer itself after a second call, and hands
// the buffer back. No lifetime's region can span such a call, so each side
// is a loan of its own, the view made again on the side that reads it. Once
// every hold is strengthened and the drops are placed, @f counts nothing:
// the buffer is lent, then given back, and no reference is taken or freed.
// @g is called twice, so it stays a function; it makes the buffer @f takes
// and drops the one @f gives back.
idr.program @loans root(@main) stage(first) {
  idr.func @main() {
    %n = arith.constant 3 : i64
    %r = idr.call @g(%n) <{tail_kind = nontail}> : (i64) -> i64
    %text = idr.str.show_sint %r : (i64) -> !idr.str
    idr.io.put_str %text : (!idr.str) -> ()
    idr.return
  }
  idr.func @f(%keep: memref<4xi64>, %n: i64) -> (memref<4xi64>, i64) {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %view = memref.subview %keep[1] [2] [1] : memref<4xi64> to memref<2xi64, strided<[1], offset: 1>>
    %a = memref.load %view[%c0] : memref<2xi64, strided<[1], offset: 1>>
    %r1 = idr.call @g(%n) <{tail_kind = nontail}> : (i64) -> i64
    %b = memref.load %view[%c1] : memref<2xi64, strided<[1], offset: 1>>
    %r2 = idr.call @g(%n) <{tail_kind = nontail}> : (i64) -> i64
    %c = memref.load %keep[%c0] : memref<4xi64>
    %ab = arith.addi %a, %b : i64
    %abc = arith.addi %ab, %c : i64
    %r = arith.addi %r1, %r2 : i64
    %sum = arith.addi %abc, %r : i64
    idr.return %keep, %sum : memref<4xi64>, i64
  }
  idr.func @g(%n: i64) -> i64 {
    %fresh = memref.alloc() : memref<4xi64>
    %back, %r = idr.call @f(%fresh, %n) <{tail_kind = nontail}> : (memref<4xi64>, i64) -> (memref<4xi64>, i64)
    idr.return %r : i64
  }
}
