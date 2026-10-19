// RUN: idris-mlir-opt %s '--idr-expect=holds=signature=@plain:(i64)->i64,convention=@step:tailcc,convention=@main:ccc' -o /dev/null
// RUN: idris-mlir-opt %s '--idr-expect=holds=signature=@plain:(i64)->i32,convention=@step:ccc,convention=@plain:ccc,entry' -verify-diagnostics -o /dev/null
// RUN: sed '/^  llvm.func @helper/,/^  }/d' %s > %t.entry.mlir
// RUN: idris-mlir-opt %t.entry.mlir --idr-expect=holds=entry -o /dev/null
// The types and the convention a lowered function is called by: @plain
// takes and returns a word, @step is called by tailcc, and only an
// llvm.func has a convention. After idr-entry @main, of the C entry's
// type, is the one public function, which @main alone would hold; @helper
// is another, and the module without it (the sed drops it) holds; private
// functions with bodies (@step, @plain) are no entry of their own.
module {
  // expected-error @below {{expected convention: }}
  llvm.func tailcc @step(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    llvm.return %x : i64
  }
  // expected-error @below {{expected signature: }}
  // expected-error @below {{expected convention: }}
  func.func private @plain(%x: i64) -> i64 {
    return %x : i64
  }
  // expected-error @below {{expected entry: }}
  llvm.func @helper(%x: i64) -> i64 {
    llvm.return %x : i64
  }
  llvm.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    llvm.return %argc : i32
  }
}
