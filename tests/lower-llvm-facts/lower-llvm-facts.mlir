// RUN: idris-mlir-opt %s --idr-rc --idr-lower > %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-expect=holds=lowered,aligned-access -o /dev/null
// RUN: FileCheck %s < %t.mlir
// RUN: idris-mlir-opt %t.mlir --idr-entry --convert-scf-to-cf --convert-to-llvm --reconcile-unrealized-casts | mlir-translate --mlir-to-llvmir | FileCheck %s --check-prefix=LL
// What the types say and the LLVM types no longer do goes to LLVM as
// attributes of the parameters and results: a box, closure or string is a
// pointer to a cell, never null, 8-aligned, with its 8-byte header to read;
// an unboxed sum's tag is below its number of constructors. Poison of a
// cell pointer is the static cell `nothing`, so a parameter some call
// passes poison is a cell too, and gets the pointer facts.
// Every load and store of a cell states its alignment, which the cell's
// layout knows. A crash is a cold call, so LLVM lays it out of the way.
// The facts are what LLVM reads, so they are checked as LLVM is given
// them: the attributes of the lowered signatures, and the translated
// module's.
// The range an op states for its result is the runtime's promise too, so a
// runtime call's result says it: an Int's text starts with '-' or a digit,
// and a character read at a byte offset is a scalar value or 0.
// What LLVM is told holds of every value the program meets, so no fact
// lets it compute another: the root, of the byte x it reads, takes the
// head of Nil (0, which crashes) or of [x], the shade of one of the three
// colours (x mod 3), the first character of x - 128 shown (a '-', or the
// first of one to three digits) through a call that also takes poison, and
// the character at byte offset x - 2 of "héllo" (before its start, at
// each of its scalars, inside the é, and past its end) plus the offset.
// The program, lowered and as written, prints what the reference at the
// end (REF) computes on words alone (%differential), on the bytes at the
// edges: 0; 1 to 4, 7 and 8 (offsets -1 to 2, 5 and 6); 128, 137, 138,
// 227, 228 and 255 (x - 128 of 0, 9, 10, 99, 100 and 127); and the end of
// input, which reads as 255.
// STDIN: \0000
// STDIN: \0001
// STDIN: \0002
// STDIN: \0003
// STDIN: \0004
// STDIN: \0007
// STDIN: \0010
// STDIN: \0200
// STDIN: \0211
// STDIN: \0212
// STDIN: \0343
// STDIN: \0344
// STDIN: \0377
// STDIN:
// CHECK-LABEL: func.func private @head(
// CHECK-SAME: !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nonnull}
// CHECK-SAME: -> (!llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nonnull})
// CHECK-LABEL: func.func private @shade(
// CHECK-SAME: i8 {llvm.range = #llvm.constant_range<i8, 0, 3>}
// CHECK-LABEL: func.func private @walk(
// CHECK-SAME: !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nonnull}
// CHECK-LABEL: func.func private @unread(
// CHECK-SAME: !llvm.ptr {llvm.align = 8 : i64, llvm.dereferenceable = 8 : i64, llvm.nonnull}
// CHECK-SAME: -> i64
// LL: define {{.*}}ptr @head(ptr nonnull align 8 dereferenceable(8) %{{[0-9]+}})
// LL: load i64, ptr %{{[0-9]+}}, align 8
// LL: call void @idris_rt_crash({{.*}}) #[[COLD:[0-9]+]]
// LL: define {{.*}}i64 @shade(i8 range(i8 0, 3) %{{[0-9]+}}
// LL: call range(i32 45, 58) i32 @idris_rt_int_head
// LL: call range(i32 0, 1114112) i32 @idris_rt_str_scalar_at
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
    default(%d: !idr.box<!List>) {
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
    %h = idr.int_head_s %x : i64
    %w = arith.extui %h : i32 to i64
    return %w : i64
  }
  idr.func @walk(%s: !idr.str, %o: i64) -> i64 {
    %c = idr.str.scalar_at %s, %o
    %w = arith.extui %c : i32 to i64
    %r = arith.addi %w, %o : i64
    return %r : i64
  }
  idr.func @unread(%l: !idr.box<!List>, %n: i64) -> i64 {
    return %n : i64
  }
  idr.func @Prog.main(%w: !idr.world) -> !idr.world {
    %c, %w1 = idr.io.get_byte %w
    %x = arith.extui %c : i32 to i64
    %nil = idr.con !idr.box<!List> @Nil()
    %l = idr.match_lit %x : i64 -> (!idr.box<!List>) {
    case 0 {
      idr.yield %nil : !idr.box<!List>
    }
    default(%d: i64) {
      %cons = idr.con !idr.box<!List> @Cons(%x : i64, %nil : !idr.box<!List>)
      idr.yield %cons : !idr.box<!List>
    }
    }
    %h = idr.call @head(%l) : (!idr.box<!List>) -> !idr.box<!List>
    %hv = idr.match %h : !idr.box<!List> -> (i64) {
    case @Cons(%a: i64, %t: !idr.box<!List>) {
      idr.yield %a : i64
    }
    default(%e: !idr.box<!List>) {
      %none = arith.constant -1 : i64
      idr.yield %none : i64
    }
    }
    %three = arith.constant 3 : i64
    %m = arith.remui %x, %three : i64
    %col = idr.match_lit %m : i64 -> (!Colour) {
    case 0 {
      %red = idr.con !Colour @Red()
      idr.yield %red : !Colour
    }
    case 1 {
      %green = idr.con !Colour @Green()
      idr.yield %green : !Colour
    }
    default(%e: i64) {
      %half = arith.constant 1.5 : f64
      %blue = idr.con !Colour @Blue(%half : f64)
      idr.yield %blue : !Colour
    }
    }
    %s = idr.call @shade(%col) : (!Colour) -> i64
    %k128 = arith.constant 128 : i64
    %v = arith.subi %x, %k128 : i64
    %p = ub.poison : !idr.box<!List>
    %u = idr.call @unread(%p, %v) : (!idr.box<!List>, i64) -> i64
    %g = idr.call @sign(%u) : (i64) -> i64
    %two = arith.constant 2 : i64
    %o = arith.subi %x, %two : i64
    %str = idr.constant !idr.str "h\C3\A9llo"
    %k = idr.call @walk(%str, %o) : (!idr.str, i64) -> i64
    %nl = arith.constant 10 : i32
    %w2 = idr.io.put_sint %hv, %w1 : i64
    %w3 = idr.io.put_char %nl, %w2
    %w4 = idr.io.put_sint %s, %w3 : i64
    %w5 = idr.io.put_char %nl, %w4
    %w6 = idr.io.put_sint %g, %w5 : i64
    %w7 = idr.io.put_char %nl, %w6
    %w8 = idr.io.put_sint %k, %w7 : i64
    %w9 = idr.io.put_char %nl, %w8
    return %w9 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@Prog.main) stage(higher) {
// REF:   idr.func @Prog.main(%w: !idr.world) -> !idr.world {
// REF:     %c, %w1 = idr.io.get_byte %w
// REF:     %x = arith.extui %c : i32 to i64
// REF:     %hv = idr.match_lit %x : i64 -> (i64) {
// REF:     case 0 {
// REF:       idr.crash "unmatched case"
// REF:       ub.unreachable
// REF:     }
// REF:     default(%d: i64) {
// REF:       %twice = arith.addi %x, %x : i64
// REF:       idr.yield %twice : i64
// REF:     }
// REF:     }
// REF:     %three = arith.constant 3 : i64
// REF:     %s = arith.remui %x, %three : i64
// REF:     %k128 = arith.constant 128 : i64
// REF:     %v = arith.subi %x, %k128 : i64
// REF:     %zero = arith.constant 0 : i64
// REF:     %ten = arith.constant 10 : i64
// REF:     %hundred = arith.constant 100 : i64
// REF:     %k48 = arith.constant 48 : i64
// REF:     %minus = arith.constant 45 : i64
// REF:     %one = arith.constant 49 : i64
// REF:     %tens = arith.divui %v, %ten : i64
// REF:     %digit = arith.addi %k48, %v : i64
// REF:     %tdigit = arith.addi %k48, %tens : i64
// REF:     %neg = arith.cmpi slt, %v, %zero : i64
// REF:     %lt10 = arith.cmpi slt, %v, %ten : i64
// REF:     %lt100 = arith.cmpi slt, %v, %hundred : i64
// REF:     %g3 = arith.select %lt100, %tdigit, %one : i64
// REF:     %g2 = arith.select %lt10, %digit, %g3 : i64
// REF:     %g = arith.select %neg, %minus, %g2 : i64
// REF:     %two = arith.constant 2 : i64
// REF:     %o = arith.subi %x, %two : i64
// REF:     %at = idr.match_lit %o : i64 -> (i64) {
// REF:     case -2 {
// REF:       %h = arith.constant 104 : i64
// REF:       idr.yield %h : i64
// REF:     }
// REF:     case -1 {
// REF:       %h = arith.constant 104 : i64
// REF:       idr.yield %h : i64
// REF:     }
// REF:     case 0 {
// REF:       %h = arith.constant 104 : i64
// REF:       idr.yield %h : i64
// REF:     }
// REF:     case 1 {
// REF:       %e = arith.constant 233 : i64
// REF:       idr.yield %e : i64
// REF:     }
// REF:     case 2 {
// REF:       %e = arith.constant 233 : i64
// REF:       idr.yield %e : i64
// REF:     }
// REF:     case 3 {
// REF:       %l = arith.constant 108 : i64
// REF:       idr.yield %l : i64
// REF:     }
// REF:     case 4 {
// REF:       %l = arith.constant 108 : i64
// REF:       idr.yield %l : i64
// REF:     }
// REF:     case 5 {
// REF:       %oo = arith.constant 111 : i64
// REF:       idr.yield %oo : i64
// REF:     }
// REF:     default(%past: i64) {
// REF:       %end = arith.constant 0 : i64
// REF:       idr.yield %end : i64
// REF:     }
// REF:     }
// REF:     %k = arith.addi %at, %o : i64
// REF:     %nl = arith.constant 10 : i32
// REF:     %w2 = idr.io.put_sint %hv, %w1 : i64
// REF:     %w3 = idr.io.put_char %nl, %w2
// REF:     %w4 = idr.io.put_sint %s, %w3 : i64
// REF:     %w5 = idr.io.put_char %nl, %w4
// REF:     %w6 = idr.io.put_sint %g, %w5 : i64
// REF:     %w7 = idr.io.put_char %nl, %w6
// REF:     %w8 = idr.io.put_sint %k, %w7 : i64
// REF:     %w9 = idr.io.put_char %nl, %w8
// REF:     return %w9 : !idr.world
// REF:   }
// REF: }
