// RUN: idris-mlir-opt %s -split-input-file --idr-lower --idr-entry '--idr-expect=holds=entry,linker-names,calls=@main:@idris_rt_start,call-order=@__idr$entry$body:[@Prog.main,@idris_rt_main_return],signature=@__idr$entry$body:()->i64' -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 0' %s > %t.status.mlir
// RUN: idris-mlir-opt %t.status.mlir --idr-lower --idr-entry '--idr-expect=holds=signature=@Prog.main:()->i64' -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 1' %s > %t.io.mlir
// RUN: idris-mlir-opt %t.io.mlir --idr-lower --idr-entry '--idr-expect=holds=signature=@Prog.main:()->(),returns=@__idr$entry$body:0' -o /dev/null
// RUN: awk '/^\/\/ -----/ { n++; next } n == 2' %s > %t.iores.mlir
// RUN: idris-mlir-opt %t.iores.mlir --idr-lower --idr-entry '--idr-expect=holds=signature=@Prog.main:()->(),returns=@__idr$entry$body:0' -o /dev/null
// RUN: sed -n 's|^// STATUS: ||p' %s > %t.status.ref.mlir
// RUN: sed -n 's|^// HI: ||p' %s > %t.hi.ref.mlir
// RUN: idris-mlir-opt %t.status.mlir --idr-lower -o %t.status.lowered.mlir
// RUN: %differential %t.status.ref.mlir %t.status.lowered.mlir
// RUN: idris-mlir-opt %t.io.mlir --idr-lower -o %t.io.lowered.mlir
// RUN: %differential %t.hi.ref.mlir %t.io.lowered.mlir
// RUN: idris-mlir-opt %t.iores.mlir --idr-lower -o %t.iores.lowered.mlir
// RUN: %differential %t.hi.ref.mlir %t.iores.lowered.mlir
// idr-entry makes the lowered root the program's entry: @main, the one
// public function, takes the program's arguments, the count and the
// vector, and hands them to the runtime's entry with @__idr$entry$body,
// whose status it returns. @__idr$entry$body calls the root, which is no
// longer public, then ends main in the runtime. The root's lowered type is its kind: `() -> i64` gives
// the status, and an IO root, `() -> ()` once its world is gone, gives 0;
// the frontend's IO root returns the world with an IORes of unit, which
// holds no runtime component, so it lowers to `() -> ()` too.
// And the entry runs the root: lowered and linked, the status root's
// program exits with 3, and each IO root's prints hi and exits with 0, as
// the references at the end (STATUS, HI), with no constructor and no
// string, do (%differential, on the one input, none, since none reads).
// STDIN:
idr.program @entry root(@Prog.main) stage(owned) types #idr.types<> {
  idr.func @Prog.main() -> i64 {
    %c = arith.constant 3 : i64
    return %c : i64
  }
}

// -----

idr.program @entry root(@Prog.main) stage(owned) types #idr.types<> {
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %s = idr.constant !idr.str "hi\0A"
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
}

// -----

!IORes = !idr.data<"IORes">
#types = #idr.types<
  "IORes" = plain [@MkIORes(!idr.data<"Unit">, !idr.world)],
  "Unit" = plain [@MkUnit()]
>
idr.program @entry root(@Prog.main) stage(owned) types #types {
  idr.func @Prog.main(%w: !idr.world) -> !IORes {
    %s = idr.constant !idr.str "hi\0A"
    %w1 = idr.io.put_str %s, %w
    %u = idr.con !idr.data<"Unit"> @MkUnit()
    %r = idr.con !IORes @MkIORes(%u : !idr.data<"Unit">, %w1 : !idr.world)
    return %r : !IORes
  }
}
// The references:
// STATUS: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// STATUS:   idr.func @Prog.main() -> i64 {
// STATUS:     %c = arith.constant 3 : i64
// STATUS:     return %c : i64
// STATUS:   }
// STATUS: }
// HI: idr.program @ref root(@Prog.main) stage(higher) types #idr.types<> {
// HI:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// HI:     %h = arith.constant 104 : i32
// HI:     %i = arith.constant 105 : i32
// HI:     %nl = arith.constant 10 : i32
// HI:     %w1 = idr.io.put_char %h, %w
// HI:     %w2 = idr.io.put_char %i, %w1
// HI:     %w3 = idr.io.put_char %nl, %w2
// HI:     return %w3 : !idr.world
// HI:   }
// HI: }
