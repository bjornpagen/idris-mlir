// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,signature=@f:(i32)->(),calls-only=@f:[@idris_rt_io_put_char]' -o /dev/null
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// A forged world has no runtime form, like every world: what is left of a
// chain on one is the IO it did. And it does it: the root reads a byte and
// gives its character to @f, and the program, lowered and as written,
// prints it, as the reference at the end (REF), on the root's own world,
// does (%differential, on 0, 65, 128, 255 and the end of input).
// STDIN: \0000
// STDIN: A
// STDIN: \0200
// STDIN: \0377
// STDIN:
idr.program @world root(@root) stage(owned) {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    idr.call @f(%c) : (i32) -> ()
    return %w1 : !idr.world
  }
  idr.func @f(%c: i32) {
    %w = idr.world.new
    %w1 = idr.io.put_char %c, %w
    return
  }
}
// The reference:
// REF: idr.program @ref root(@root) stage(higher) {
// REF:   idr.func @root(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %w2 = idr.io.put_char %c, %w1
// REF:     return %w2 : !idr.world
// REF:   }
// REF: }
