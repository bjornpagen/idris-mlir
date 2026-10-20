// mlir-opt --canonicalize: the square root of -2.5 stays a math.sqrt.
func.func @sqrt_negative() -> f64 {
  %c = arith.constant -2.5 : f64
  %r = math.sqrt %c : f64
  return %r : f64
}
