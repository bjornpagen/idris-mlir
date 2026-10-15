// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=lowered,crash-sites=@byte:1,calls-only=@byte:[@idris_rt_crash],returns-argument=@byte:0 -o /dev/null
// RUN: FileCheck %s < %t.mlir
// The guard of an Int written as a byte crashes unless the Int is 0 to 255:
// a negative one is a large unsigned one, so one comparison above 255
// tests both ends. Its message is its cause at its location, the one the
// partial primitive had: the program ends with the same text.
// CHECK: llvm.mlir.constant("idris-mlir: a byte outside 0 to 255 at Prog.idr:6:1\0A")
idr.program @"byte-message" root(@Prog.main) stage(owned) {
  idr.func @byte(%x: i64) -> i64 {
    %y = idr.check.byte %x, "a byte outside 0 to 255" loc("Prog.idr":6:1)
    return %y : i64
  }
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 7 : i64
    %b = idr.call @byte(%c) : (i64) -> i64
    return %b : i64
  }
}
