// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,crash-sites=@byte:1,calls-only=@byte:[@idris_rt_crash],signature=@byte:(i64)->i8' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=no-guards=@constant,returns=@constant:-56 -o /dev/null
// An Int written as a byte: its guard crashes unless it is 0 to 255 (a
// negative Int is a large unsigned one), and gives it on; then the low byte
// is the result, with no test of its own. A constant byte's guard folds,
// and so does the byte: 200 is the byte -56.
idr.program @"to-byte" root(@root) stage(owned) {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %in, %w1 = idr.io.get_byte %w
    %x = arith.extui %in : i32 to i64
    %b = idr.call @byte(%x) : (i64) -> i8
    %c = idr.call @constant() : () -> i8
    return %w1 : !idr.world
  }
  idr.func @byte(%x: i64) -> i8 {
    %y = idr.check.byte %x, "a byte outside 0 to 255"
    %b = idr.to_byte %y
    return %b : i8
  }
  idr.func @constant() -> i8 {
    %x = arith.constant 200 : i64
    %y = idr.check.byte %x, "a byte outside 0 to 255"
    %b = idr.to_byte %y
    return %b : i8
  }
}
