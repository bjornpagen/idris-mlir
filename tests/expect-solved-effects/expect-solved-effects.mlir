// RUN: idris-mlir-opt %s --idr-expect=holds=effects=@pure:none,effects=@divides:crash,effects=@unsolved:io+crash+diverge,effects=@unsolved:diverge+io+crash,effects=@writes:crash+io -o /dev/null
// RUN: idris-mlir-opt %s --idr-expect=holds=effects=@pure:crash,effects=@divides:none,effects=@writes:io -verify-diagnostics -o /dev/null
// What a function may do is the set it holds: none for one that only
// computes and is total (@pure), crash for one whose guard may (@divides),
// and everything for one no pass solved, which holds the default
// (@unsolved). A set is a set: written in any order it is the same, and
// one of its two effects is not it (@writes, io and crash).
idr.program @"solved-effects" root(@root) stage(first) {
  // expected-error @below {{expected effects: }}
  idr.func effects<none> @pure(%x: i64) -> i64 attributes {total} {
    %y = arith.addi %x, %x : i64
    return %y : i64
  }
  // expected-error @below {{expected effects: }}
  idr.func effects<crash> @divides(%x: i64, %y: i64) -> i64 attributes {total} {
    %g = idr.check.nonzero %y, "division by zero" : i64
    %q = idr.divs %x, %g : i64
    return %q : i64
  }
  // expected-error @below {{expected effects: }}
  idr.func effects<io, crash> @writes(%x: i64, %w: !idr.world) -> (i64, !idr.world) attributes {total} {
    %g = idr.check.nonzero %x, "division by zero" : i64
    %c = arith.constant 65 : i32
    %w1 = idr.io.put_char %c, %w
    return %g, %w1 : i64, !idr.world
  }
  idr.func @unsolved(%x: i64) -> i64 {
    return %x : i64
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
