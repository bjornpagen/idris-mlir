// NEEDS-ACCEPTANCE: that the -verify-diagnostics run passes: signature and convention each fail at each function given another type or convention, or no convention to have, and entry only at the second public function, @main being of the C entry's type.
// RUN: idris-mlir-opt %s '--idr-expect=holds=signature=@plain:(i64)->i64,convention=@step:tailcc,convention=@main:ccc' -o /dev/null
// RUN: idris-mlir-opt %s '--idr-expect=holds=signature=@plain:(i64)->i32,convention=@step:ccc,convention=@plain:ccc,entry' -verify-diagnostics -o /dev/null
// The types and the convention a lowered function is called by: @plain
// takes and returns a word, @step is called by tailcc, and only an
// llvm.func has a convention. After idr-entry @main, of the C entry's
// type, is the one public function, which @main alone would hold; @helper
// is another.
module {
  // expected-error @below {{expected convention: @step is called by tailcc, not ccc}}
  llvm.func tailcc @step(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    llvm.return %x : i64
  }
  // expected-error @below {{expected signature: @plain has the type (i64) -> i64, not (i64) -> i32}}
  // expected-error @below {{expected convention: @plain is no llvm.func, which has a convention}}
  func.func private @plain(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error @below {{expected entry: @helper is public, and only @main is}}
  llvm.func @helper(%x: i64) -> i64 {
    llvm.return %x : i64
  }
  llvm.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    llvm.return %argc : i32
  }
}
