// RUN: idris-mlir-opt %s --idr-lower > %t.mlir
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts | mlir-translate --mlir-to-llvmir | FileCheck %s --check-prefix=LL
// What the types say and the LLVM types no longer do goes to LLVM as
// attributes of the parameters and results: a box, closure or string is a
// pointer to a cell, never null, 8-aligned, with its 8-byte header to read;
// an unboxed sum's tag is below its number of constructors. A parameter
// that some call passes poison may be null, and gets no pointer facts.
// Every load and store of a cell states its alignment, which the cell's
// layout knows. A crash is a cold call, so LLVM lays it out of the way.
// The range an op states for its result is the runtime's promise too, so a
// runtime call's result says it: an Int's text starts with '-' or a digit.
// CHECK-LABEL: func.func private @head(
// CHECK-SAME: !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nonnull}
// CHECK-SAME: -> (!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nonnull})
// CHECK-LABEL: func.func private @shade(
// CHECK-SAME: i8 {llvm.range = #llvm.constant_range<i8, 0, 3>}
// CHECK-LABEL: func.func private @unread(
// CHECK-NOT: llvm.nonnull
// CHECK-SAME: -> i64
// CHECK-NOT: llvm.load %{{[0-9a-z_]+}} :
// CHECK-NOT: llvm.store %{{[0-9a-z_]+}}, %{{[0-9a-z_]+}} :
// LL: define {{.*}}ptr @head(ptr nonnull align 8 dereferenceable(8) %{{[0-9]+}})
// LL: load i64, ptr %{{[0-9]+}}, align 8
// LL: call void @idris_rt_crash({{.*}}) #[[COLD:[0-9]+]]
// LL: define {{.*}}i64 @shade(i8 range(i8 0, 3) %{{[0-9]+}}
// LL: call range(i32 45, 58) i32 @idris_rt_int_head
// LL: attributes #[[COLD]] = { cold noreturn }
module attributes {idr.program} {
  idr.data @List box {
    idr.ctor @Nil ()
    idr.ctor @Cons (i64, !idr.box<@List>)
  }
  idr.data @Colour {
    idr.ctor @Red ()
    idr.ctor @Green ()
    idr.ctor @Blue (f64)
  }
  // The tail of a list that is not empty; a crash otherwise.
  func.func private @head(%l: !idr.box<@List>) -> !idr.box<@List> {
    %r = idr.match %l : !idr.box<@List> -> (!idr.box<@List>) {
    case @Cons(%x: i64, %t: !idr.box<@List>) {
      %s = arith.addi %x, %x : i64
      %c = idr.con @List::@Cons(%s, %t) : (i64, !idr.box<@List>) -> !idr.box<@List>
      idr.yield %c : !idr.box<@List>
    }
    default {
      idr.crash "unmatched case"
      ub.unreachable
    }
    }
    return %r : !idr.box<@List>
  }
  func.func private @shade(%c: !idr.data<@Colour>) -> i64 {
    %t = idr.tag %c : !idr.data<@Colour>
    return %t : i64
  }
  func.func private @sign(%x: i64) -> i64 {
    %h = idr.int_head signed %x : i64
    %w = arith.extui %h : i32 to i64
    return %w : i64
  }
  func.func private @unread(%l: !idr.box<@List>, %n: i64) -> i64 {
    return %n : i64
  }
  func.func @Prog.main() -> i64 {
    %n = arith.constant 3 : i64
    %nil = idr.con @List::@Nil() : () -> !idr.box<@List>
    %l = idr.con @List::@Cons(%n, %nil) : (i64, !idr.box<@List>) -> !idr.box<@List>
    %h = func.call @head(%l) : (!idr.box<@List>) -> !idr.box<@List>
    %red = idr.con @Colour::@Red() : () -> !idr.data<@Colour>
    %s = func.call @shade(%red) : (!idr.data<@Colour>) -> i64
    %p = ub.poison : !idr.box<@List>
    %u = func.call @unread(%p, %s) : (!idr.box<@List>, i64) -> i64
    %g = func.call @sign(%u) : (i64) -> i64
    return %g : i64
  }
}
