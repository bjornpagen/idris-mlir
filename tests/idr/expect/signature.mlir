// NEEDS-ACCEPTANCE: that signature and convention fail once for each function given another type or convention, or no convention to have, and that entry holds of the CLEAN module and fails once, at the second public function.
// RUN: sed -n 's|^// CLEAN: ||p' %s > %t.clean.mlir
// RUN: idris-mlir-opt %s '--idr-expect=holds=signature=@plain:(i64)->i64,convention=@step:tailcc,convention=@main:ccc' -o /dev/null
// RUN: idris-mlir-opt %t.clean.mlir --idr-expect=holds=entry -o /dev/null
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=signature=@plain:(i64)->i32,convention=@step:ccc,convention=@plain:ccc,entry' -o /dev/null 2> %t.err
// RUN: FileCheck %s < %t.err
// RUN: grep 'error: expected ' %t.err | count 4
// The types and the convention a lowered function is called by: @plain
// takes and returns a word, @step is called by tailcc, and only an
// llvm.func has a convention. After idr-entry @main, of the C entry's
// type, is the one public function (the CLEAN module); @helper is another.
// CHECK-DAG: error: expected signature: @plain has the type {{.*}}, not {{.*}}
// CHECK-DAG: error: expected convention: @step is called by {{.*}}, not {{.*}}
// CHECK-DAG: error: expected convention: @plain is no llvm.func, which has a convention
// CHECK-DAG: error: expected entry: @helper is public, and only @main is
// CLEAN: module {
// CLEAN:   llvm.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
// CLEAN:     llvm.return %argc : i32
// CLEAN:   }
// CLEAN: }
module {
  llvm.func tailcc @step(%x: i64) -> i64 attributes {sym_visibility = "private"} {
    llvm.return %x : i64
  }
  func.func private @plain(%x: i64) -> i64 {
    return %x : i64
  }
  llvm.func @helper(%x: i64) -> i64 {
    llvm.return %x : i64
  }
  llvm.func @main(%argc: i32, %argv: !llvm.ptr) -> i32 {
    llvm.return %argc : i32
  }
}
