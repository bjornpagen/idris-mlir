// mlir-opt --canonicalize: at the pin, the square root of -2.5 stays a
// math.sqrt; with the patch it folds to a quiet NaN.
func.func @sqrt_negative() -> f64 {
  %c = arith.constant -2.5 : f64
  %r = math.sqrt %c : f64
  return %r : f64
}
