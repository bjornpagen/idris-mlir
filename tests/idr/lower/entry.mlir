// NEEDS-ACCEPTANCE: the entry body and the release function have their reserved names (S30); the third program, the frontend's IO root `(!idr.world) -> !IORes`, lowers to `() -> ()` and its entry body returns 0 (conversion-8, S38).
// RUN: idris-mlir-opt %s -split-input-file --idr-lower --idr-entry '--idr-expect=holds=entry,linker-names,calls=@main:@idris_rt_start,call-order=@__idr$entry$body:[@Prog.main,@__idr$release$cafs,@idris_rt_main_return],signature=@__idr$entry$body:()->i64' -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 0' %s > %t.status.mlir
// RUN: idris-mlir-opt %t.status.mlir --idr-lower --idr-entry '--idr-expect=holds=signature=@Prog.main:()->i64' -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 1' %s > %t.io.mlir
// RUN: idris-mlir-opt %t.io.mlir --idr-lower --idr-entry '--idr-expect=holds=signature=@Prog.main:()->(),returns=@__idr$entry$body:0' -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 2' %s > %t.iores.mlir
// RUN: idris-mlir-opt %t.iores.mlir --idr-lower --idr-entry '--idr-expect=holds=signature=@Prog.main:()->(),returns=@__idr$entry$body:0' -o /dev/null
// idr-entry makes the lowered root the program's entry: @main, the one
// public function, takes the program's arguments, the count and the
// vector, and hands them to the runtime's entry with @__idr$entry$body,
// whose status it returns. @__idr$entry$body calls the root, which is no
// longer public, then releases what the static thunks hold, then ends main
// in the runtime. The root's lowered type is its kind: `() -> i64` gives
// the status, and an IO root, `() -> ()` once its world is gone, gives 0;
// the frontend's IO root returns the world with an IORes of unit, which
// holds no runtime component, so it lowers to `() -> ()` too.
idr.program @entry root(@Prog.main) stage(owned) {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 3 : i64
    return %c : i64
  }
}

// -----

idr.program @entry root(@Prog.main) stage(owned) {
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %s = idr.constant !idr.str "hi\0A"
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
}

// -----

!IORes = !idr.data<"IORes", plain [@MkIORes(!idr.data<"Unit", plain [@MkUnit()]>, !idr.world)]>
idr.program @entry root(@Prog.main) stage(owned) {
  idr.func @Prog.main(%w: !idr.world) -> !IORes {
    %s = idr.constant !idr.str "hi\0A"
    %w1 = idr.io.put_str %s, %w
    %u = idr.con !idr.data<"Unit", plain [@MkUnit()]> @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !idr.data<"Unit", plain [@MkUnit()]>, %w1 : !idr.world)
    return %r : !IORes
  }
}
