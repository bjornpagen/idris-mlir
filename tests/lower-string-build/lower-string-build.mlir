// RUN: idris-mlir-opt %s --idr-lower -o %t.mlir
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=lowered,never-calls=@pack:@idris_rt_str_cons,never-calls=@pack:@idris_rt_str_append,call-order=@pack:[@idris_rt_str_alloc,@idris_rt_str_put_char],loops=@pack:2' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=never-calls=@concat:@idris_rt_str_append,call-order=@concat:[@idris_rt_str_alloc,@idris_rt_str_put_str],loops=@concat:2' -o /dev/null
// RUN: idris-mlir-opt %t.mlir '--idr-expect=holds=calls-only=@write_chars:[@idris_rt_io_put_char],loops=@write_chars:1,calls-only=@write_strs:[@idris_rt_io_put_str],loops=@write_strs:1' -o /dev/null
// A string built from a list is allocated once, at the size a first walk
// of the list counts, and written in a second walk: no string is built per
// element (no cons or append of strings). A list written without its
// string is walked once, each element going to the output as put_char or
// put_str writes it, and nothing is allocated.
!Chars = !idr.data<"Chars", list [@Nil() nil, @Cons(i32, !idr.box<!idr.data<"Chars">>) cons]>
!Strs = !idr.data<"Strs", list [@Nil() nil, @Cons(!idr.str, !idr.box<!idr.data<"Strs">>) cons]>
idr.program @"string-build" root(@root) stage(owned) {
  idr.func @root(%w: !idr.world) -> !idr.world {
    %cs = idr.constant !idr.q<many, borrow, !idr.box<!Chars>> #idr.con<!Chars, @Nil, []>
    %ss = idr.constant !idr.q<many, borrow, !idr.box<!Strs>> #idr.con<!Strs, @Nil, []>
    %a = idr.call @pack(%cs) : (!idr.q<many, borrow, !idr.box<!Chars>>) -> !idr.own<!idr.str>
    %b = idr.call @concat(%ss) : (!idr.q<many, borrow, !idr.box<!Strs>>) -> !idr.own<!idr.str>
    idr.drop %a : !idr.own<!idr.str>
    idr.drop %b : !idr.own<!idr.str>
    %w1 = idr.call @write_chars(%cs, %w) : (!idr.q<many, borrow, !idr.box<!Chars>>, !idr.world) -> !idr.world
    %w2 = idr.call @write_strs(%ss, %w1) : (!idr.q<many, borrow, !idr.box<!Strs>>, !idr.world) -> !idr.world
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
