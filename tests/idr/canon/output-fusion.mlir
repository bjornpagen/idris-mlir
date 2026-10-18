// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=output-fused,no-heap-allocation=@append,\
// RUN: no-heap-allocation=@cons,no-heap-allocation=@from_char,no-heap-allocation=@shows,\
// RUN: no-heap-allocation=@lists,no-heap-allocation=@line,no-heap-allocation=@constant_list,\
// RUN: returns-argument=@nil:0,builds-nothing=@cell,no-heap-allocation=@cell,\
// RUN: no-heap-allocation=@cells_of_strings,builds=@cell_kept,no-heap-allocation=@packed_in_a_region -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// A string built only to be written is written piece by piece, in the
// same order, through the world: nothing is built for output alone, so a
// function that only writes allocates nothing, and one whose string or
// cell has another use keeps it for that use.

// "n = " ++ show n ++ "\n": three writes.
!Chars = !idr.data<"Chars", list [@Nil() nil, @Cons(i32, !idr.box<!idr.data<"Chars">>) cons]>
!Strs = !idr.data<"Strs", list [@Nil() nil, @Cons(!idr.str, !idr.box<!idr.data<"Strs">>) cons]>
idr.program @"output-fusion" root(@constant_list) stage(first) {
  idr.func @append(%n: i64, %w: !idr.world) -> !idr.world {
    %a = idr.constant !idr.str "n = "
    %nl = idr.constant !idr.str "\n"
    %s = idr.str.show_sint %n : i64
    %t = idr.str.append %s, %nl
    %u = idr.str.append %a, %t
    %w1 = idr.io.put_str %u, %w
    return %w1 : !idr.world
  }

  idr.func @cons(%c: i32, %s: !idr.str, %w: !idr.world) -> !idr.world {
    %t = idr.str.cons %c, %s
    %w1 = idr.io.put_str %t, %w
    return %w1 : !idr.world
  }

  idr.func @from_char(%c: i32, %w: !idr.world) -> !idr.world {
    %t = idr.str.from_char %c
    %w1 = idr.io.put_str %t, %w
    return %w1 : !idr.world
  }

  idr.func @shows(%b: i8, %d: f64, %w: !idr.world) -> !idr.world {
    %s = idr.str.show_uint %b : i8
    %w1 = idr.io.put_str %s, %w
    %t = idr.str.show_double %d
    %w2 = idr.io.put_str %t, %w1
    return %w2 : !idr.world
  }

  // A string with another use is still written piece by piece; it stays for
  // that use.
  idr.func @shared(%c: i32, %w: !idr.world) -> (!idr.world, !idr.str) {
    %s = idr.str.from_char %c
    %w1 = idr.io.put_str %s, %w
    return %w1, %s : !idr.world, !idr.str
  }

  // putStr (pack cs) and putStr (concat ss): each list is written as it is
  // walked, and no string is built.
  idr.func @lists(%cs: !idr.box<!Chars>, %ss: !idr.box<!Strs>, %w: !idr.world) -> !idr.world {
    %s = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
    %w1 = idr.io.put_str %s, %w
    %t = idr.str.concat %ss : !idr.box<!Strs> -> !idr.str
    %w2 = idr.io.put_str %t, %w1
    return %w2 : !idr.world
  }

  // putStrLn (pack cs): the line's characters, then its end.
  idr.func @line(%cs: !idr.box<!Chars>, %w: !idr.world) -> !idr.world {
    %nl = idr.constant !idr.str "\n"
    %s = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
    %l = idr.str.append %s, %nl
    %w1 = idr.io.put_str %l, %w
    return %w1 : !idr.world
  }

  // A packed string with another use is built anyway, and written as it is.
  idr.func @packed_and_kept(%cs: !idr.box<!Chars>, %w: !idr.world) -> (!idr.world, !idr.str) {
    %s = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
    %w1 = idr.io.put_str %s, %w
    return %w1, %s : !idr.world, !idr.str
  }

  // A list that is a constant is written as the string it packs to, which is
  // what writing its pack wrote: compile-time evaluation can make the list a
  // constant after the output of its pack became a walk.
  idr.func @constant_list(%w: !idr.world) -> !idr.world {
    %cs = idr.constant !idr.box<!Chars> #idr.con<!Chars, @Cons, [104 : i32, #idr.con<!Chars, @Cons, [105 : i32, #idr.con<!Chars, @Nil, []>]>]>
    %w1 = idr.io.put_list %cs, %w : !idr.box<!Chars>
    return %w1 : !idr.world
  }

  // Writing the nil writes nothing.
  idr.func @nil(%w: !idr.world) -> !idr.world {
    %ss = idr.con !idr.box<!Strs> @Nil()
    %w1 = idr.io.put_list %ss, %w : !idr.box<!Strs>
    return %w1 : !idr.world
  }

  // Writing a cell writes its element, then the rest, and the cell built
  // only to be written is not built: putStrLn (pack ('>' :: header)) writes
  // the character, then the header as it walks it.
  idr.func @cell(%header: !idr.box<!Chars>, %w: !idr.world) -> !idr.world {
    %gt = arith.constant 62 : i32
    %l = idr.con !idr.box<!Chars> @Cons(%gt : i32, %header : !idr.box<!Chars>)
    %s = idr.str.pack %l : !idr.box<!Chars> -> !idr.str
    %nl = idr.constant !idr.str "\n"
    %t = idr.str.append %s, %nl
    %w1 = idr.io.put_str %t, %w
    return %w1 : !idr.world
  }

  // The cells of a list of strings: each string as put_str writes it, the
  // last cell's tail a constant nil, which writes nothing.
  idr.func @cells_of_strings(%a: !idr.str, %b: !idr.str, %w: !idr.world) -> !idr.world {
    %nil = idr.con !idr.box<!Strs> @Nil()
    %l1 = idr.con !idr.box<!Strs> @Cons(%b : !idr.str, %nil : !idr.box<!Strs>)
    %l2 = idr.con !idr.box<!Strs> @Cons(%a : !idr.str, %l1 : !idr.box<!Strs>)
    %s = idr.str.concat %l2 : !idr.box<!Strs> -> !idr.str
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }

  // A cell with another use is built anyway: it is written as it is walked.
  idr.func @cell_kept(%header: !idr.box<!Chars>, %w: !idr.world) -> (!idr.world, !idr.box<!Chars>) {
    %gt = arith.constant 62 : i32
    %l = idr.con !idr.box<!Chars> @Cons(%gt : i32, %header : !idr.box<!Chars>)
    %w1 = idr.io.put_list %l, %w : !idr.box<!Chars>
    return %w1, %l : !idr.world, !idr.box<!Chars>
  }

  // Output of a string that one region of a match packs, and another takes
  // as a constant, moves into the match: the region that packs writes its
  // list as it walks it, the other writes its string.
  idr.func @packed_in_a_region(%a: i64, %cs: !idr.box<!Chars>, %w: !idr.world) -> !idr.world {
    %s = idr.match_lit %a : i64 -> (!idr.str) {
    case 0 {
      %p = idr.str.pack %cs : !idr.box<!Chars> -> !idr.str
      idr.yield %p : !idr.str
    }
    default(%d: i64) {
      %k = idr.constant !idr.str "none"
      idr.yield %k : !idr.str
    }
    }
    %w1 = idr.io.put_str %s, %w
    return %w1 : !idr.world
  }
}
