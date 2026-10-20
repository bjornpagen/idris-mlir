// RUN: idris-mlir-opt %s --idr-rc --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed 's/stage(first)/stage(higher)/' %s > %t.higher.mlir
// RUN: idris-mlir -c %t.higher.mlir -o %t.o
// RUN: %cc %t.o -o %t
// RUN: printf '1234567890\n\003' | %t | FileCheck %s --match-full-lines --check-prefix=VALUES
// RUN: printf '\n\002' | %status 1 %t > %t.index.out 2> %t.index.err
// RUN: FileCheck %s --check-prefix=INDEX --match-full-lines < %t.index.err
// RUN: printf 'hello\n\000' | %status 1 %t > %t.divisor.out 2> %t.divisor.err
// RUN: FileCheck %s --check-prefix=DIVISOR --match-full-lines < %t.divisor.err
// RUN: printf 'hello\n\001' | %status 1 %t > %t.infinite.out 2> %t.infinite.err
// RUN: FileCheck %s --check-prefix=INFINITE --match-full-lines < %t.infinite.err
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,crash-sites=@strings:3,crash-sites=@bigs:3,crash-sites=@doubles:1' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=call-order=@strings:[@idris_rt_str_show_s,@idris_rt_str_show_u,@idris_rt_str_show_f64],call-order=@doubles:[@idris_rt_to_int,@idris_rt_double_head,@idris_rt_int_head_s]' -o /dev/null
// String and big ops call the runtime function their op declares, a big
// op's small case inline in the runtime's own function
// (big-fast-path.mlir). Where a primitive may crash, its guard tests first and
// crashes: an index out of range, the head or tail of "", a big divisor of
// 0, a non-finite Double; the op it guards then tests nothing, so each
// function may crash at its guards and nowhere else. show and the casts
// pick their function by the operand's signedness or type, and a cast to
// a narrower integer takes the value modulo 2^64 and truncates it.
// The root reads a line s and a byte c, and gives every function values
// of them (c / (c - 1) as the Double), so that each guard is reached: the
// index c past the end of s, the divisor 0, the Double 1 / 0. The program,
// lowered and as written, prints and exits alike on each input below
// (%differential), and compiled whole by idris-mlir (stage higher, which a
// program with no closure may say), it prints each primitive's result as
// the runtime defines it, or crashes at the guard the input reaches, its
// cause and its place on stderr.
// VALUES: 12345678901234567890
// VALUES-NEXT: 11
// VALUES-NEXT: 1
// VALUES-NEXT: 3
// VALUES-NEXT: 3
// VALUES-NEXT: 1.5
// VALUES-NEXT: 52
// VALUES-NEXT: 49
// VALUES-NEXT: 234567890
// VALUES-NEXT: 456
// VALUES-NEXT: 0987654321
// VALUES-NEXT: 1
// VALUES-NEXT: 722
// VALUES-NEXT: 1234567890.0
// VALUES-NEXT: 6
// VALUES-NEXT: 1
// VALUES-NEXT: 0
// VALUES-NEXT: -3
// VALUES-NEXT: 0
// VALUES-NEXT: 3
// VALUES-NEXT: 3
// VALUES-NEXT: 1
// VALUES-NEXT: 3.0
// VALUES-NEXT: 3
// VALUES-NEXT: 1234567890
// VALUES-NEXT: 1
// VALUES-NEXT: 49
// VALUES-NEXT: 51
// STDIN: 1234567890\n\0003
// STDIN: \n\0002
// STDIN: hello\n\0000
// STDIN: hello\n\0001
// STDIN: hi\n\0005
// STDIN: -12.5e3\n\0003
// STDIN:
idr.program @"strings-bigs" root(@Prog.main) stage(first) types #idr.types<> {
  idr.func @strings(%s: !idr.str, %i: i64, %c: i32, %n: i32, %d: f64) -> (!idr.str, !idr.str,
      !idr.str, !idr.str, !idr.str, !idr.str, i32, i32, !idr.str, !idr.str, !idr.str, i1, i16, f64) {
    %a = idr.str.append %s, %s
    %b = idr.str.cons %c, %s
    %f = idr.str.from_char %c
    %t1 = idr.str.show_sint %n : i32
    %t2 = idr.str.show_uint %n : i32
    %t3 = idr.str.show_double %d
    %len = idr.str.length %s
    // INDEX: idris-mlir: string index out of range at {{.*}}higher.mlir:[[#@LINE+1]]:11
    %ix = idr.check.in_bounds %i, %s, "string index out of range" : !idr.str
    %x = idr.str.index %s, %ix
    %hs = idr.check.nonempty %s, "head of an empty string" : !idr.str
    %h = idr.str.head %hs
    %ts = idr.check.nonempty %s, "tail of an empty string" : !idr.str
    %tl = idr.str.tail %ts
    %sub = idr.str.substr %s, %i, %i
    %r = idr.str.reverse %s
    %lte = idr.str.cmp lte %s, %s
    %k = idr.str.to_int %s : i16
    %v = idr.str.to_double %s
    return %a, %b, %f, %t1, %t2, %t3, %x, %h, %tl, %sub, %r, %lte, %k, %v
        : !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, i32, i32, !idr.str,
          !idr.str, !idr.str, i1, i16, f64
  }
  idr.func @bigs(%a: !idr.big, %b: !idr.big, %d: f64, %s: !idr.str, %y: i8)
      -> (!idr.big, !idr.big, !idr.big, !idr.big, i1, !idr.big, i32, !idr.big, f64, !idr.str, !idr.big) {
    %sum = idr.big.add %a, %b
    // DIVISOR: idris-mlir: division by zero at {{.*}}higher.mlir:[[#@LINE+1]]:11
    %qb = idr.check.nonzero %b, "division by zero" : !idr.big
    %q = idr.big.div %a, %qb
    %mb = idr.check.nonzero %b, "division by zero" : !idr.big
    %m = idr.big.mod %a, %mb
    %n = idr.big.neg %a
    %gt = idr.big.cmp gt %a, %b
    %u = idr.big.from_uint %y : i8
    %w = idr.big.to_int %a : i32
    // INFINITE: idris-mlir: cast of a non-finite Double at {{.*}}higher.mlir:[[#@LINE+1]]:12
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
    %g = idr.int_head_s %n : i16
    return %i, %h, %g : i8, i32, i32
  }
  // The root calls each function on values read at run time, so that each
  // is part of the program.
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %s, %w1 = idr.io.get_line %w
    %c, %w2 = idr.io.get_byte %w1
    %i = arith.extsi %c : i32 to i64
    %one = arith.constant 1 : i32
    %c1 = arith.subi %c, %one : i32
    %num = arith.sitofp %c : i32 to f64
    %den = arith.sitofp %c1 : i32 to f64
    %d = arith.divf %num, %den : f64
    %y = arith.trunci %c : i32 to i8
    %n16 = arith.trunci %c : i32 to i16
    %a = idr.big.from_sint %c : i32
    %b = idr.big.from_sint %i : i64
    %r1:14 = idr.call @strings(%s, %i, %c, %c, %d) : (!idr.str, i64, i32, i32, f64) -> (!idr.str, !idr.str,
        !idr.str, !idr.str, !idr.str, !idr.str, i32, i32, !idr.str, !idr.str, !idr.str, i1, i16, f64)
    %r2:11 = idr.call @bigs(%a, %b, %d, %s, %y) : (!idr.big, !idr.big, f64, !idr.str, i8)
        -> (!idr.big, !idr.big, !idr.big, !idr.big, i1, !idr.big, i32, !idr.big, f64, !idr.str, !idr.big)
    %r3:3 = idr.call @doubles(%d, %n16) : (f64, i16) -> (i8, i32, i32)
    %nl = arith.constant 10 : i32
    %w3 = idr.io.put_str %r1#0, %w2
    %w4 = idr.io.put_char %nl, %w3
    %blen = idr.str.length %r1#1
    %w5 = idr.io.put_sint %blen, %w4 : i64
    %w6 = idr.io.put_char %nl, %w5
    %flen = idr.str.length %r1#2
    %w7 = idr.io.put_sint %flen, %w6 : i64
    %w8 = idr.io.put_char %nl, %w7
    %w9 = idr.io.put_str %r1#3, %w8
    %w10 = idr.io.put_char %nl, %w9
    %w11 = idr.io.put_str %r1#4, %w10
    %w12 = idr.io.put_char %nl, %w11
    %w13 = idr.io.put_str %r1#5, %w12
    %w14 = idr.io.put_char %nl, %w13
    %w15 = idr.io.put_sint %r1#6, %w14 : i32
    %w16 = idr.io.put_char %nl, %w15
    %w17 = idr.io.put_sint %r1#7, %w16 : i32
    %w18 = idr.io.put_char %nl, %w17
    %w19 = idr.io.put_str %r1#8, %w18
    %w20 = idr.io.put_char %nl, %w19
    %w21 = idr.io.put_str %r1#9, %w20
    %w22 = idr.io.put_char %nl, %w21
    %w23 = idr.io.put_str %r1#10, %w22
    %w24 = idr.io.put_char %nl, %w23
    %lte = arith.extui %r1#11 : i1 to i64
    %w25 = idr.io.put_sint %lte, %w24 : i64
    %w26 = idr.io.put_char %nl, %w25
    %w27 = idr.io.put_sint %r1#12, %w26 : i16
    %w28 = idr.io.put_char %nl, %w27
    %w29 = idr.io.put_double %r1#13, %w28
    %w30 = idr.io.put_char %nl, %w29
    %showsum = idr.big.show %r2#0
    %w31 = idr.io.put_str %showsum, %w30
    %w32 = idr.io.put_char %nl, %w31
    %showq = idr.big.show %r2#1
    %w33 = idr.io.put_str %showq, %w32
    %w34 = idr.io.put_char %nl, %w33
    %showm = idr.big.show %r2#2
    %w35 = idr.io.put_str %showm, %w34
    %w36 = idr.io.put_char %nl, %w35
    %shown = idr.big.show %r2#3
    %w37 = idr.io.put_str %shown, %w36
    %w38 = idr.io.put_char %nl, %w37
    %gt = arith.extui %r2#4 : i1 to i64
    %w39 = idr.io.put_sint %gt, %w38 : i64
    %w40 = idr.io.put_char %nl, %w39
    %showu = idr.big.show %r2#5
    %w41 = idr.io.put_str %showu, %w40
    %w42 = idr.io.put_char %nl, %w41
    %w43 = idr.io.put_sint %r2#6, %w42 : i32
    %w44 = idr.io.put_char %nl, %w43
    %showfd = idr.big.show %r2#7
    %w45 = idr.io.put_str %showfd, %w44
    %w46 = idr.io.put_char %nl, %w45
    %w47 = idr.io.put_double %r2#8, %w46
    %w48 = idr.io.put_char %nl, %w47
    %w49 = idr.io.put_str %r2#9, %w48
    %w50 = idr.io.put_char %nl, %w49
    %showfs = idr.big.show %r2#10
    %w51 = idr.io.put_str %showfs, %w50
    %w52 = idr.io.put_char %nl, %w51
    %w53 = idr.io.put_sint %r3#0, %w52 : i8
    %w54 = idr.io.put_char %nl, %w53
    %w55 = idr.io.put_sint %r3#1, %w54 : i32
    %w56 = idr.io.put_char %nl, %w55
    %w57 = idr.io.put_sint %r3#2, %w56 : i32
    %w58 = idr.io.put_char %nl, %w57
    return %w58 : !idr.world
  }
}
