// RUN: idris-mlir-opt %s --idr-rc --idr-lower > %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=lowered,aligned-access -o /dev/null
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-entry --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts | mlir-translate --mlir-to-llvmir | FileCheck %s --check-prefix=LL
// NEEDS-ACCEPTANCE: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
// What the types say and the LLVM types no longer do goes to LLVM as
// attributes of the parameters and results: a box, closure or string is a
// pointer to a cell, never null, 8-aligned, with its 8-byte header to read;
// an unboxed sum's tag is below its number of constructors. A parameter
// that some call passes poison may be null, and gets no pointer facts.
// Every load and store of a cell states its alignment, which the cell's
// layout knows. A crash is a cold call, so LLVM lays it out of the way.
// The facts are what LLVM reads, so they are checked as LLVM is given
// them: the attributes of the lowered signatures, and the translated
// module's.
// The range an op states for its result is the runtime's promise too, so a
// runtime call's result says it: an Int's text starts with '-' or a digit,
// a character read at a byte offset is a scalar value or 0, and the offset
// after it is not negative.
// CHECK-LABEL: func.func private @head(
// CHECK-SAME: !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nonnull}
// CHECK-SAME: -> (!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nonnull})
// CHECK-LABEL: func.func private @shade(
// CHECK-SAME: i8 {llvm.range = #llvm.constant_range<i8, 0, 3>}
// CHECK-LABEL: func.func private @walk(
// CHECK-SAME: !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nonnull}
// CHECK-LABEL: func.func private @unread(
// CHECK-NOT: llvm.nonnull
// CHECK-SAME: -> i64
// LL: define {{.*}}ptr @head(ptr nonnull align 8 dereferenceable(8) %{{[0-9]+}})
// LL: load i64, ptr %{{[0-9]+}}, align 8
// LL: call void @idris_rt_crash({{.*}}) #[[COLD:[0-9]+]]
// LL: define {{.*}}i64 @shade(i8 range(i8 0, 3) %{{[0-9]+}}
// LL: call range(i32 45, 58) i32 @idris_rt_int_head
// LL: call range(i32 0, 1114112) i32 @idris_rt_str_scalar_at
// LL: call range(i64 0, -9223372036854775808) i64 @idris_rt_str_scalar_end
// LL: attributes #[[COLD]] = { cold noreturn }
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
!Colour = !idr.data<"Colour", plain [@Red(), @Green(), @Blue(f64)]>
idr.program @"llvm-facts" root(@Prog.main) stage(first) {
  // The tail of a list that is not empty; a crash otherwise.
  idr.func @head(%l: !idr.box<!List>) -> !idr.box<!List> {
    %r = idr.match %l : !idr.box<!List> -> (!idr.box<!List>) {
    case @Cons(%x: i64, %t: !idr.box<!List>) {
      %s = arith.addi %x, %x : i64
      %c = idr.con !idr.box<!List> @Cons(%s : i64, %t : !idr.box<!List>)
      idr.yield %c : !idr.box<!List>
    }
    default {
      idr.crash "unmatched case"
      ub.unreachable
    }
    }
    return %r : !idr.box<!List>
  }
  idr.func @shade(%c: !Colour) -> i64 {
    %t = idr.tag %c : !Colour
    return %t : i64
  }
  idr.func @sign(%x: i64) -> i64 {
    %h = idr.int_head signed %x : i64
    %w = arith.extui %h : i32 to i64
    return %w : i64
  }
  idr.func @walk(%s: !idr.str, %o: i64) -> i64 {
    %c = idr.str.scalar_at %s, %o
    %e = idr.str.scalar_end %s, %o
    %w = arith.extui %c : i32 to i64
    %r = arith.addi %w, %e : i64
    return %r : i64
  }
  idr.func @unread(%l: !idr.box<!List>, %n: i64) -> i64 {
    return %n : i64
  }
  idr.func @Prog.main() -> i64 {
    %n = arith.constant 3 : i64
    %nil = idr.con !idr.box<!List> @Nil()
    %l = idr.con !idr.box<!List> @Cons(%n : i64, %nil : !idr.box<!List>)
    %h = idr.call @head(%l) : (!idr.box<!List>) -> !idr.box<!List>
    %red = idr.con !Colour @Red()
    %s = idr.call @shade(%red) : (!Colour) -> i64
    %p = ub.poison : !idr.box<!List>
    %u = idr.call @unread(%p, %s) : (!idr.box<!List>, i64) -> i64
    %g = idr.call @sign(%u) : (i64) -> i64
    %str = idr.constant "h\C3\A9llo" : !idr.str
    %k = idr.call @walk(%str, %g) : (!idr.str, i64) -> i64
    return %k : i64
  }
}
