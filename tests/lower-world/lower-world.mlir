// RUN: idris-mlir-opt %s --idr-lower '--idr-expect=holds=lowered,signature=@f:(i32)->(),calls-only=@f:[@idris_rt_io_put_char]' -o /dev/null
// A forged world has no runtime form, like every world: what is left of a
// chain on one is the IO it did.
idr.program @world root(@root) stage(owned) {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c = arith.constant 65 : i32
    idr.call @f(%c) : (i32) -> ()
    return %w : !idr.world
  }
  idr.func @f(%c: i32) {
    %w = idr.world.new
    %w1 = idr.io.put_char %c, %w
    return
  }
}
