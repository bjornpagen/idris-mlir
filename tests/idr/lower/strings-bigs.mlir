// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,crash-sites=@strings:3,crash-sites=@bigs:3,crash-sites=@doubles:1' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=call-order=@strings:[@idris_rt_str_show_s,@idris_rt_str_show_u,@idris_rt_str_show_f64],call-order=@doubles:[@idris_rt_to_int,@idris_rt_double_head,@idris_rt_int_head_s]' -o /dev/null
// NEEDS-ACCEPTANCE: the input is a program of the first stage, which idr-rc counts first: at the owned stage every reference of ours is graded, so the checks are of the counted program; confirm them against it.
// String and big ops call the runtime function their op declares, a big
// op's small case inline in the runtime's own function
// (big-fast-path.mlir). Where a primitive may crash, its guard tests first and
// crashes: an index out of range, the head or tail of "", a big divisor of
// 0, a non-finite Double; the op it guards then tests nothing, so each
// function may crash at its guards and nowhere else. show and the casts
// pick their function by the operand's signedness or type, and a cast to
// a narrower integer takes the value modulo 2^64 and truncates it.
idr.program @"strings-bigs" root(@Prog.main) stage(first) {
  idr.func @strings(%s: !idr.str, %i: i64, %c: i32, %n: i32, %d: f64) -> (!idr.str, !idr.str,
      !idr.str, !idr.str, !idr.str, !idr.str, i32, i32, !idr.str, !idr.str, !idr.str, i1, i16, f64) {
    %a = idr.str.append %s, %s
    %b = idr.str.cons %c, %s
    %f = idr.str.from_char %c
    %t1 = idr.str.show signed %n : i32
    %t2 = idr.str.show %n : i32
    %t3 = idr.str.show %d : f64
    %len = idr.str.length %s
    %ix = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
    %x = idr.str.index %s, %ix
    %hs = idr.check.nonempty %s, "head of an empty string" : !idr.str
    %h = idr.str.head %hs
    %ts = idr.check.nonempty %s, "tail of an empty string" : !idr.str
    %tl = idr.str.tail %ts
    %sub = idr.str.substr %s, %i, %i
    %r = idr.str.reverse %s
    %lte = idr.str.cmp lte %s, %s
    %k = idr.str.to_int signed %s : i16
    %v = idr.str.to_double %s
    return %a, %b, %f, %t1, %t2, %t3, %x, %h, %tl, %sub, %r, %lte, %k, %v
        : !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, i32, i32, !idr.str,
          !idr.str, !idr.str, i1, i16, f64
  }
  idr.func @bigs(%a: !idr.big, %b: !idr.big, %d: f64, %s: !idr.str, %y: i8)
      -> (!idr.big, !idr.big, !idr.big, !idr.big, i1, !idr.big, i32, !idr.big, f64, !idr.str, !idr.big) {
    %sum = idr.big.add %a, %b
    %qb = idr.check.nonzero %b, "division by zero" : !idr.big
    %q = idr.big.div %a, %qb
    %mb = idr.check.nonzero %b, "division by zero" : !idr.big
    %m = idr.big.mod %a, %mb
    %n = idr.big.neg %a
    %gt = idr.big.cmp gt %a, %b
    %u = idr.big.from_int %y : i8
    %w = idr.big.to_int %a : i32
    %fdd = idr.check.finite %d, "cast of a non-finite Double"
    %fd = idr.big.from_double %fdd
    %td = idr.big.to_double %a
    %sh = idr.big.show %a
    %fs = idr.big.from_str %s
    return %sum, %q, %m, %n, %gt, %u, %w, %fd, %td, %sh, %fs
        : !idr.big, !idr.big, !idr.big, !idr.big, i1, !idr.big, i32, !idr.big, f64, !idr.str, !idr.big
  }
  idr.func @doubles(%d: f64, %n: i16) -> (i8, i32, i32) {
    %dd = idr.check.finite %d, "cast of a non-finite Double"
    %i = idr.to_int %dd : i8
    %h = idr.double_head %d
    %g = idr.int_head signed %n : i16
    return %i, %h, %g : i8, i32, i32
  }
  idr.func @Prog.main() -> i64 {
    %z = arith.constant 0 : i64
    return %z : i64
  }
}
