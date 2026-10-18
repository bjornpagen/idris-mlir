// RUN: idris-mlir-opt %s --idr-lower --idr-entry -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,entry,linker-names,calls-only=@Prog.main:[@__idr_main,@__idr_release_cafs],call-order=@__idr$entry$body:[@Prog.main,@__idr$release$cafs,@idris_rt_main_return]' -o /dev/null
// NEEDS-ACCEPTANCE: that functions the program names as the entry body and the release function were once named lower beside the compiler's own, which the root's entry body calls.
// The compiler's own symbols are named apart from the program's: a
// mangled name has a digit after its first `$`, and each name the compiler
// makes (idr::reservedName) a letter. So a program may name its functions
// what the entry body and the release function were once named, and they
// lower as any other function, called by the root, beside the entry body
// and the release function.
idr.program @reserved root(@Prog.main) stage(owned) {
  idr.func @__idr_main() -> i64 {
    %c = arith.constant 1 : i64
    return %c : i64
  }
  idr.func @__idr_release_cafs() -> i64 {
    %c = arith.constant 2 : i64
    return %c : i64
  }
  idr.func @Prog.main() -> i64 {
    %a = idr.call @__idr_main() : () -> i64
    %b = idr.call @__idr_release_cafs() : () -> i64
    %s = arith.addi %a, %b : i64
    return %s : i64
  }
}
