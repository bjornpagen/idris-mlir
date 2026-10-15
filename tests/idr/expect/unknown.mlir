// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=breaks-last -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: %status 1 idris-mlir-opt %s --idr-expect=holds=every-cycle-has-breaker,in-bounds=@f,bounds-checked=@f,pure-array-loops -o /dev/null 2> %t.gone.err
// RUN: FileCheck %s --check-prefix=GONE < %t.gone.err
// A property idr-expect does not know is an error, so a misspelled name,
// or a property of a mechanism that is gone, cannot pass where it stands.
// CHECK: error: idr-expect: no property named breaks-last
// GONE-DAG: error: idr-expect: no property named every-cycle-has-breaker
// GONE-DAG: error: idr-expect: no property named in-bounds
// GONE-DAG: error: idr-expect: no property named bounds-checked
// GONE-DAG: error: idr-expect: no property named pure-array-loops
module {
  idr.func private @f(%x: i64) -> i64 {
    return %x : i64
  }
}
