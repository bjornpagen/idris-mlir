// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-effects -o %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=no-closures,forces-nothing=@forcesBoom,forces-nothing=@echo,forces-nothing=@Prog.main,effects=@forcesBoom:crash,by-name=@shout,by-name=@echo,not-by-name=@boom -o /dev/null
// RUN: sed -n 's|^// REFERENCE: ||p' %s > %t.reference.mlir
// RUN: %differential %s %t.reference.mlir
// RUN: %differential %t.mlir %t.reference.mlir
// RUN: sed 's/"11"/"1"/' %t.reference.mlir > %t.wrong.mlir
// RUN: not %differential %s %t.wrong.mlir 2>&1 | FileCheck %s
// Making a suspension runs nothing: what its label may do counts where the
// cell is forced, and after defunctionalization a force is a call of the
// memo sum's dispatch, which calls the label: so a function that forces a
// cell whose label may crash may crash (@forcesBoom). A label whose run
// the outside can see, made at run time, runs again at every force: it is
// by name (@shout). A label that forces a cell by name is by name itself
// (@echo): forcing it runs that output again. A label that only crashes is
// not (@boom).
//
// So the program, which forces the cell of @echo twice and then calls
// @forcesBoom, writes 1 at each force, from @shout, run again through
// @echo each time, and then crashes: 11 and the crash, as the REFERENCE
// lines do, before defunctionalization and after. A reference that writes
// 1 once, as a program whose by-name label kept its value would, is told
// apart.
// CHECK: differential: effects-forced-labels.mlir and {{.*}}wrong.mlir differ on ''
// STDIN:
idr.program @"forced-labels" root(@Prog.main) stage(higher) {
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
    %w1 = idr.io.put_sint %n, %w : i64
    return %n : i64
  }
  idr.func @echo(%t: !idr.lazy<i64>) -> i64 attributes {total} {
    %v = idr.force %t : !idr.lazy<i64> -> i64
    return %v : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c = arith.constant 1 : i64
    %s = idr.suspend @shout(%c) : (i64) -> !idr.lazy<i64>
    %e = idr.suspend @echo(%s) : (!idr.lazy<i64>) -> !idr.lazy<i64>
    %v = idr.force %e : !idr.lazy<i64> -> i64
    %u = idr.force %e : !idr.lazy<i64> -> i64
    %b = idr.call @forcesBoom() : () -> i64
    %vu = arith.addi %v, %u : i64
    %s2 = arith.addi %vu, %b : i64
    %w1 = idr.io.put_sint %s2, %w : i64
    return %w1 : !idr.world
  }
}
// REFERENCE: idr.program @reference root(@Prog.main) stage(higher) {
// REFERENCE:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REFERENCE:     %s = idr.constant !idr.str "11"
// REFERENCE:     %w1 = idr.io.put_str %s, %w
// REFERENCE:     idr.crash "boom"
// REFERENCE:     ub.unreachable
// REFERENCE:   }
// REFERENCE: }
