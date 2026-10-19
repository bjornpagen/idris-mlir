// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: %differential %s %t.mlir
// RUN: sed -n 's|^// REF: ||p' %s > %t.ref.mlir
// RUN: %differential %t.ref.mlir %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,never-calls=@pack:@idris_rt_str_cons,never-calls=@pack:@idris_rt_str_append,call-order=@pack:[@idris_rt_str_alloc,@idris_rt_str_put_char],loops=@pack:2' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=never-calls=@concat:@idris_rt_str_append,call-order=@concat:[@idris_rt_str_alloc,@idris_rt_str_put_str],loops=@concat:2' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=calls-only=@write_chars:[@idris_rt_io_put_char],loops=@write_chars:1,calls-only=@write_strs:[@idris_rt_io_put_str],loops=@write_strs:1' -o /dev/null
// A string built from a list is allocated once, at the size a first walk
// of the list counts, and written in a second walk: no string is built per
// element (no cons or append of strings). A list written without its
// string is walked once, each element going to the output as put_char or
// put_str writes it, and nothing is allocated.
// The first walk counts bytes, not elements: the root packs and writes the
// characters h, é and U+1F600 (one, two and four bytes of UTF-8), and
// concatenates and writes the strings "ab", "" and "cdé", then does each
// to the empty lists. The program, lowered and as written, prints what
// the reference at the end (REF) writes a character at a time: those
// three characters twice and abcdé twice, a line each, and four empty
// lines (%differential, on the one input, none, since it reads none).
// STDIN:
!Chars = !idr.data<"Chars", list [@Nil() nil, @Cons(i32, !idr.box<!idr.data<"Chars">>) cons]>
!Strs = !idr.data<"Strs", list [@Nil() nil, @Cons(!idr.str, !idr.box<!idr.data<"Strs">>) cons]>
idr.program @"string-build" root(@root) stage(owned) {
  idr.func @all(%cs: !idr.q<many, borrow, !idr.box<!Chars>>, %ss: !idr.q<many, borrow, !idr.box<!Strs>>, %w: !idr.world) -> !idr.world {
    %nl = arith.constant 10 : i32
    %a = idr.call @pack(%cs) : (!idr.q<many, borrow, !idr.box<!Chars>>) -> !idr.own<!idr.str>
    %ab = idr.borrow %a : !idr.own<!idr.str>
    %w1 = idr.io.put_str borrow %ab, %w
    idr.drop %a : !idr.own<!idr.str>
    %w2 = idr.io.put_char %nl, %w1
    %w3 = idr.call @write_chars(%cs, %w2) : (!idr.q<many, borrow, !idr.box<!Chars>>, !idr.world) -> !idr.world
    %w4 = idr.io.put_char %nl, %w3
    %b = idr.call @concat(%ss) : (!idr.q<many, borrow, !idr.box<!Strs>>) -> !idr.own<!idr.str>
    %bb = idr.borrow %b : !idr.own<!idr.str>
    %w5 = idr.io.put_str borrow %bb, %w4
    idr.drop %b : !idr.own<!idr.str>
    %w6 = idr.io.put_char %nl, %w5
    %w7 = idr.call @write_strs(%ss, %w6) : (!idr.q<many, borrow, !idr.box<!Strs>>, !idr.world) -> !idr.world
    %w8 = idr.io.put_char %nl, %w7
    return %w8 : !idr.world
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %cs = idr.constant !idr.q<many, borrow, !idr.box<!Chars>> #idr.con<!Chars, @Cons, [104 : i32, #idr.con<!Chars, @Cons, [233 : i32, #idr.con<!Chars, @Cons, [128512 : i32, #idr.con<!Chars, @Nil, []>]>]>]>
    %ss = idr.constant !idr.q<many, borrow, !idr.box<!Strs>> #idr.con<!Strs, @Cons, ["ab", #idr.con<!Strs, @Cons, ["", #idr.con<!Strs, @Cons, ["cd\C3\A9", #idr.con<!Strs, @Nil, []>]>]>]>
    %w1 = idr.call @all(%cs, %ss, %w) : (!idr.q<many, borrow, !idr.box<!Chars>>, !idr.q<many, borrow, !idr.box<!Strs>>, !idr.world) -> !idr.world
    %ec = idr.constant !idr.q<many, borrow, !idr.box<!Chars>> #idr.con<!Chars, @Nil, []>
    %es = idr.constant !idr.q<many, borrow, !idr.box<!Strs>> #idr.con<!Strs, @Nil, []>
    %w2 = idr.call @all(%ec, %es, %w1) : (!idr.q<many, borrow, !idr.box<!Chars>>, !idr.q<many, borrow, !idr.box<!Strs>>, !idr.world) -> !idr.world
    return %w2 : !idr.world
  }
  idr.func @pack(%xs: !idr.q<many, borrow, !idr.box<!Chars>>) -> !idr.own<!idr.str> {
    %s = idr.str.pack %xs : !idr.q<many, borrow, !idr.box<!Chars>> -> !idr.own<!idr.str>
    return %s : !idr.own<!idr.str>
  }
  idr.func @concat(%xs: !idr.q<many, borrow, !idr.box<!Strs>>) -> !idr.own<!idr.str> {
    %s = idr.str.concat %xs : !idr.q<many, borrow, !idr.box<!Strs>> -> !idr.own<!idr.str>
    return %s : !idr.own<!idr.str>
  }
  idr.func @write_chars(%xs: !idr.q<many, borrow, !idr.box<!Chars>>, %w: !idr.world) -> !idr.world {
    %w1 = idr.io.put_list %xs, %w : !idr.q<many, borrow, !idr.box<!Chars>>
    return %w1 : !idr.world
  }
  idr.func @write_strs(%xs: !idr.q<many, borrow, !idr.box<!Strs>>, %w: !idr.world) -> !idr.world {
    %w1 = idr.io.put_list %xs, %w : !idr.q<many, borrow, !idr.box<!Strs>>
    return %w1 : !idr.world
  }
}
// The reference:
// REF: idr.program @ref root(@root) stage(higher) {
// REF:   idr.func @chars(%w: !idr.world) -> !idr.world {
// REF:     %h = arith.constant 104 : i32
// REF:     %e = arith.constant 233 : i32
// REF:     %smile = arith.constant 128512 : i32
// REF:     %nl = arith.constant 10 : i32
// REF:     %w1 = idr.io.put_char %h, %w
// REF:     %w2 = idr.io.put_char %e, %w1
// REF:     %w3 = idr.io.put_char %smile, %w2
// REF:     %w4 = idr.io.put_char %nl, %w3
// REF:     return %w4 : !idr.world
// REF:   }
// REF:   idr.func @strs(%w: !idr.world) -> !idr.world {
// REF:     %a = arith.constant 97 : i32
// REF:     %b = arith.constant 98 : i32
// REF:     %c = arith.constant 99 : i32
// REF:     %d = arith.constant 100 : i32
// REF:     %e = arith.constant 233 : i32
// REF:     %nl = arith.constant 10 : i32
// REF:     %w1 = idr.io.put_char %a, %w
// REF:     %w2 = idr.io.put_char %b, %w1
// REF:     %w3 = idr.io.put_char %c, %w2
// REF:     %w4 = idr.io.put_char %d, %w3
// REF:     %w5 = idr.io.put_char %e, %w4
// REF:     %w6 = idr.io.put_char %nl, %w5
// REF:     return %w6 : !idr.world
// REF:   }
// REF:   idr.func @root(%w: !idr.world) -> !idr.world {
// REF:     %w1 = idr.call @chars(%w) : (!idr.world) -> !idr.world
// REF:     %w2 = idr.call @chars(%w1) : (!idr.world) -> !idr.world
// REF:     %w3 = idr.call @strs(%w2) : (!idr.world) -> !idr.world
// REF:     %w4 = idr.call @strs(%w3) : (!idr.world) -> !idr.world
// REF:     %nl = arith.constant 10 : i32
// REF:     %w5 = idr.io.put_char %nl, %w4
// REF:     %w6 = idr.io.put_char %nl, %w5
// REF:     %w7 = idr.io.put_char %nl, %w6
// REF:     %w8 = idr.io.put_char %nl, %w7
// REF:     return %w8 : !idr.world
// REF:   }
// REF: }
