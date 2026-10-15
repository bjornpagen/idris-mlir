// RUN: idris-mlir-opt %s -split-input-file --idr-lower --idr-entry '--idr-expect=holds=entry,linker-names,calls=@main:@idris_rt_start,call-order=@__idr_main:[@Prog.main,@__idr_release_cafs,@idris_rt_main_return],signature=@__idr_main:()->i64' -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 0' %s > %t.status.mlir
// RUN: idris-mlir-opt %t.status.mlir --idr-lower --idr-entry '--idr-expect=holds=signature=@Prog.main:()->i64' -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 1' %s > %t.io.mlir
// RUN: idris-mlir-opt %t.io.mlir --idr-lower --idr-entry '--idr-expect=holds=signature=@Prog.main:()->(),returns=@__idr_main:0' -o /dev/null
// idr-entry makes the lowered root the program's entry: @main, the one
// public function, takes the program's arguments, the count and the
// vector, and hands them to the runtime's entry with @__idr_main, whose
// status it returns. @__idr_main calls the root, which is no longer
// public, then releases what the static thunks hold, then ends main in the
// runtime. The root's lowered type is its kind: `() -> i64` gives the
// status, and an IO root, `() -> ()` once its world is gone, gives 0.
idr.program @entry root(@Prog.main) stage(owned) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 3 : i64
    return %c : i64
  }
}

// -----

idr.program @entry root(@Prog.main) stage(owned) {
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %s = idr.constant "hi\0A" : !idr.str
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
}
