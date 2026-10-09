// Two ops whose operands and results fit 32 bits, which
// arith-int-range-narrowing at llvmorg-23.1.2 narrows to i32 forms that
// compute something else. The clamps (maxsi, minsi) are what the analysis
// bounds.

// x in [-2^31, 0], y in [-2, -1]: x rem y fits, but INT32_MIN rem -1
// overflows on i32 (llvm.srem: undefined behaviour), where it is 0 on i64.
func.func @rem(%x: i64, %y: i64) -> i64 {
  %xmin = arith.constant -2147483648 : i64
  %zero = arith.constant 0 : i64
  %ymin = arith.constant -2 : i64
  %ymax = arith.constant -1 : i64
  %x1 = arith.maxsi %x, %xmin : i64
  %a = arith.minsi %x1, %zero : i64
  %y1 = arith.maxsi %y, %ymin : i64
  %b = arith.minsi %y1, %ymax : i64
  %r = arith.remsi %a, %b : i64
  return %r : i64
}

// x in [-2, 0]: x urem 7 fits, but the narrowed remui reads -2 as
// 2^32 - 2 where the i64 one reads 2^64 - 2: (2^64 - 2) % 7 = 0, while
// (2^32 - 2) % 7 = 2.
func.func @remu(%x: i64) -> i64 {
  %xmin = arith.constant -2 : i64
  %zero = arith.constant 0 : i64
  %c7 = arith.constant 7 : i64
  %x1 = arith.maxsi %x, %xmin : i64
  %a = arith.minsi %x1, %zero : i64
  %r = arith.remui %a, %c7 : i64
  return %r : i64
}

// 0 before the narrowing; 2 after it, once inlined and folded.
func.func @remu_of_minus_two() -> i64 {
  %m2 = arith.constant -2 : i64
  %r = func.call @remu(%m2) : (i64) -> i64
  return %r : i64
}
