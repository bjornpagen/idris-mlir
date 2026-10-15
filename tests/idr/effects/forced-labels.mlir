// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-effects -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures,forces-nothing=@forcesBoom,forces-nothing=@echo,forces-nothing=@main,effects=@forcesBoom:crash,by-name=@shout,by-name=@echo,not-by-name=@boom -o /dev/null
// NEEDS-ACCEPTANCE: that idr-defunctionalize turns each force into a call of its memo sum's dispatch (R06) and marks the labels by_name as the effects say (C10).
// Making a suspension runs nothing: what its label may do counts where the
// cell is forced, and after defunctionalization a force is a call of the
// memo sum's dispatch, which calls the label: so a function that forces a
// cell whose label may crash may crash (@forcesBoom). A label whose run
// the outside can see, made at run time, runs again at every force: it is
// by name (@shout). A label that forces a cell by name is by name itself
// (@echo): forcing it runs that output again. A label that only crashes is
// not (@boom).
idr.program @"forced-labels" root(@main) stage(higher) {
  idr.func @boom() -> i64 attributes {total} {
    idr.crash "boom"
    ub.unreachable
  }
  idr.func @forcesBoom() -> i64 attributes {total} {
    %t = idr.suspend @boom() : () -> !idr.lazy<i64>
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @shout(%n: i64) -> i64 attributes {total} {
    %w = idr.world.new
    %w1 = idr.io.put_int signed %n, %w : i64
    return %n : i64
  }
  idr.func @echo(%t: !idr.lazy<i64>) -> i64 attributes {total} {
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @main(%w: !idr.world) -> !idr.world {
    %c = arith.constant 1 : i64
    %s = idr.suspend @shout(%c) : (i64) -> !idr.lazy<i64>
    %e = idr.suspend @echo(%s) : (!idr.lazy<i64>) -> !idr.lazy<i64>
    %v = idr.force %e : !idr.lazy<i64> -> i64
    %b = idr.call @forcesBoom() : () -> i64
    %s2 = arith.addi %v, %b : i64
    %w1 = idr.io.put_int signed %s2, %w : i64
    return %w1 : !idr.world
  }
}
