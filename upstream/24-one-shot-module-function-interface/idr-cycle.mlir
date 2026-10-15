// A recursive idr.func whose every level writes, in place, the array the
// level below returns: the analysis of the cycle of calls finds that @build
// returns a writable buffer of its own allocation, so no level copies it.
idr.program @"idr-cycle" root(@root) stage(first) {
  idr.func private @build(%n: index) -> tensor<8xi64> {
    %c0 = arith.constant 0 : index
    %c1 = arith.constant 1 : index
    %v = arith.constant 7 : i64
    %done = arith.cmpi eq, %n, %c0 : index
    %r = scf.if %done -> tensor<8xi64> {
      %t = tensor.splat %v : tensor<8xi64>
      scf.yield %t : tensor<8xi64>
    } else {
      %m = arith.subi %n, %c1 : index
      %t = idr.call @build(%m) : (index) -> tensor<8xi64>
      %i = arith.index_cast %m : index to i64
      %t1 = tensor.insert %i into %t[%m] : tensor<8xi64>
      scf.yield %t1 : tensor<8xi64>
    }
    return %r : tensor<8xi64>
  }
  idr.func private @root(%w: !idr.world) -> !idr.world {
    %c3 = arith.constant 3 : index
    %c8 = arith.constant 8 : index
    %t = idr.call @build(%c8) : (index) -> tensor<8xi64>
    %x = tensor.extract %t[%c3] : tensor<8xi64>
    %w2 = idr.io.put_int signed %x, %w : i64
    return %w2 : !idr.world
  }
}
