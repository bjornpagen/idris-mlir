// RUN: idris-mlir-opt %s --idr-lower | FileCheck %s
// String and big ops call the runtime function named after them; those of
// bigs whose small case is inline (big-fast-path.mlir) call it only on
// their cold path, and are not checked here. Where an
// op may crash, the lowering checks first: an index out of range, the head
// or tail of "", a big divisor of 0 (the small word 1), a non-finite Double.
// Casts to integers get the value modulo 2^64 and truncate it; show picks
// its function by the operand's signedness or type.
// CHECK-LABEL: func.func private @strings(
// CHECK: llvm.call @idris_rt_str_append(%arg0, %arg0)
// CHECK: llvm.call @idris_rt_str_cons(%arg2, %arg0)
// CHECK: llvm.call @idris_rt_str_from_char(%arg2)
// CHECK: %[[X:.*]] = arith.extsi %arg3 : i32 to i64
// CHECK: llvm.call @idris_rt_str_show_s(%[[X]])
// CHECK: llvm.call @idris_rt_str_show_u(
// CHECK: llvm.call @idris_rt_str_show_f64(%arg4)
// CHECK: %[[LEN:.*]] = llvm.call @idris_rt_str_length(%arg0) : (!llvm.ptr) -> i64
// CHECK: %[[OUT:.*]] = arith.cmpi uge, %arg1, %[[LEN]] : i64
// CHECK: scf.if %[[OUT]] {
// CHECK: llvm.call @idris_rt_crash
// CHECK: llvm.call @idris_rt_str_index(%arg0, %arg1) : (!llvm.ptr, i64) -> i32
// CHECK: llvm.call @idris_rt_str_head(%arg0)
// CHECK: llvm.call @idris_rt_str_tail(%arg0)
// CHECK: llvm.call @idris_rt_str_substr(%arg0, %arg1, %arg1)
// CHECK: llvm.call @idris_rt_str_reverse(%arg0)
// CHECK: %[[O:.*]] = llvm.call @idris_rt_str_cmp(%arg0, %arg0) : (!llvm.ptr, !llvm.ptr) -> i32
// CHECK: arith.cmpi sle, %[[O]], %{{.*}} : i32
// CHECK: %[[W:.*]] = llvm.call @idris_rt_str_to_int(%arg0) : (!llvm.ptr) -> i64
// CHECK: arith.trunci %[[W]] : i64 to i16
// CHECK: llvm.call @idris_rt_str_to_double(%arg0) : (!llvm.ptr) -> f64
// CHECK-LABEL: func.func private @bigs(
// CHECK: %[[ZERO:.*]] = arith.cmpi eq, %arg1, %{{.*}} : i64
// CHECK: scf.if %[[ZERO]] {
// CHECK: llvm.call @idris_rt_big_div(%arg0, %arg1)
// CHECK: llvm.call @idris_rt_big_mod(%arg0, %arg1)
// CHECK: llvm.call @idris_rt_big_neg(%arg0)
// CHECK: math.isfinite %arg2 : f64
// CHECK: llvm.call @idris_rt_big_from_double(%arg2)
// CHECK: llvm.call @idris_rt_big_to_double(%arg0) : (i64) -> f64
// CHECK: llvm.call @idris_rt_big_show(%arg0) : (i64) -> !llvm.ptr
// CHECK: llvm.call @idris_rt_big_from_str(%arg3) : (!llvm.ptr) -> i64
// CHECK-LABEL: func.func private @doubles(
// CHECK: math.isfinite %arg0 : f64
// CHECK: %[[I:.*]] = llvm.call @idris_rt_to_int(%arg0) : (f64) -> i64
// CHECK: arith.trunci %[[I]] : i64 to i8
// CHECK: llvm.call @idris_rt_double_head(%arg0) : (f64) -> i32
// CHECK: llvm.call @idris_rt_int_head_s(
module attributes {idr.program} {
  func.func private @strings(%s: !idr.str, %i: i64, %c: i32, %n: i32, %d: f64) -> (!idr.str, !idr.str,
      !idr.str, !idr.str, !idr.str, !idr.str, i32, i32, !idr.str, !idr.str, !idr.str, i1, i16, f64) {
    %a = idr.str.append %s, %s
    %b = idr.str.cons %c, %s
    %f = idr.str.from_char %c
    %t1 = idr.str.show signed %n : i32
    %t2 = idr.str.show %n : i32
    %t3 = idr.str.show %d : f64
    %x = idr.str.index %s, %i
    %h = idr.str.head %s
    %tl = idr.str.tail %s
    %sub = idr.str.substr %s, %i, %i
    %r = idr.str.reverse %s
    %lte = idr.str.cmp lte %s, %s
    %k = idr.str.to_int signed %s : i16
    %v = idr.str.to_double %s
    return %a, %b, %f, %t1, %t2, %t3, %x, %h, %tl, %sub, %r, %lte, %k, %v
        : !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, i32, i32, !idr.str,
          !idr.str, !idr.str, i1, i16, f64
  }
  func.func private @bigs(%a: !idr.big, %b: !idr.big, %d: f64, %s: !idr.str, %y: i8)
      -> (!idr.big, !idr.big, !idr.big, !idr.big, i1, !idr.big, i32, !idr.big, f64, !idr.str, !idr.big) {
    %sum = idr.big.add %a, %b
    %q = idr.big.div %a, %b
    %m = idr.big.mod %a, %b
    %n = idr.big.neg %a
    %gt = idr.big.cmp gt %a, %b
    %u = idr.big.from_int %y : i8
    %w = idr.big.to_int %a : i32
    %fd = idr.big.from_double %d
    %td = idr.big.to_double %a
    %sh = idr.big.show %a
    %fs = idr.big.from_str %s
    return %sum, %q, %m, %n, %gt, %u, %w, %fd, %td, %sh, %fs
        : !idr.big, !idr.big, !idr.big, !idr.big, i1, !idr.big, i32, !idr.big, f64, !idr.str, !idr.big
  }
  func.func private @doubles(%d: f64, %n: i16) -> (i8, i32, i32) {
    %i = idr.to_int %d : i8
    %h = idr.double_head %d
    %g = idr.int_head signed %n : i16
    return %i, %h, %g : i8, i32, i32
  }
  func.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
