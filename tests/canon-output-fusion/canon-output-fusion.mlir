// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=output-fused,no-heap-allocation=@append,\
// RUN: no-heap-allocation=@cons,no-heap-allocation=@from_char,no-heap-allocation=@shows,\
// RUN: no-heap-allocation=@lists,no-heap-allocation=@line,no-heap-allocation=@constant_list,\
// RUN: returns-argument=@nil:0,builds-nothing=@cell,no-heap-allocation=@cell,\
// RUN: no-heap-allocation=@cells_of_strings,builds=@cell_kept,no-heap-allocation=@packed_in_a_region -o /dev/null
// RUN: idris-mlir-opt %s '--canonicalize=region-simplify=disabled test-convergence=true' -o /dev/null
// RUN: idris-mlir-opt %s --canonicalize -o %t.mlir
// RUN: %status 1 idris-mlir-opt %s '--idr-expect=holds=output-fused,no-heap-allocation=@append,no-heap-allocation=@cons,no-heap-allocation=@from_char,no-heap-allocation=@shows,no-heap-allocation=@lists,no-heap-allocation=@line,returns-argument=@nil:0,builds-nothing=@cell,no-heap-allocation=@cell,no-heap-allocation=@cells_of_strings,no-heap-allocation=@packed_in_a_region' -o /dev/null 2> %t.before.err
// RUN: FileCheck %s --check-prefix=BEFORE < %t.before.err
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=no-heap-allocation=@shared' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=no-heap-allocation=@packed_and_kept' -o /dev/null
// RUN: %status 1 idris-mlir-opt %t.mlir '--idr-expect=holds=builds-nothing=@cell_kept' -o /dev/null
// RUN: %differential %s %t.mlir
// BEFORE-DAG: expected output-fused:
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@append
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@cons
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@from_char
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@shows
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@lists
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@line
// BEFORE-DAG: expected returns-argument: {{.*}}@nil
// BEFORE-DAG: expected builds-nothing: {{.*}}@cell
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@cell
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@cells_of_strings
// BEFORE-DAG: expected no-heap-allocation: {{.*}}@packed_in_a_region
// A string built only to be written is written piece by piece, in the
// same order, through the world: nothing is built for output alone, so a
// function that only writes allocates nothing, and one whose string or
// cell has another use keeps it for that use.
// The root runs every function on what it reads, and the program writes
// after canonicalize the bytes it wrote before, on every byte. What the
// pass makes hold did not hold before it; a string or a cell with another
// use is still built (@shared, @packed_and_kept, @cell_kept).

// "n = " ++ show n ++ "\n": three writes.
!Chars = !idr.data<"Chars">
!Strs = !idr.data<"Strs">
#types = #idr.types<
  "Chars" = list [@Nil() nil, @Cons(i32, !idr.box<!idr.data<"Chars">>) cons],
  "Strs" = list [@Nil() nil, @Cons(!idr.str, !idr.box<!idr.data<"Strs">>) cons]
>
idr.program @"output-fusion" root(@root) stage(first) types #types {
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

  // The program's root runs every function above on what it reads: the
  // byte as a character and the next one, a list of both, the byte less
  // 128 as a number, as a byte and as a quarter. What a function keeps is
  // measured, not written again.
  idr.func @root(%w: !idr.world) -> !idr.world {
    %c, %w0 = idr.io.get_byte %w
    %byte = arith.extui %c : i32 to i64
    %c128 = arith.constant 128 : i64
    %one = arith.constant 1 : i32
    %n = arith.subi %byte, %c128 : i64
    %d0 = arith.sitofp %n : i64 to f64
    %q = arith.constant 0.25 : f64
    %d = arith.mulf %d0, %q : f64
    %b = arith.trunci %c : i32 to i8
    %next = arith.addi %c, %one : i32
    %nilc = idr.con !idr.box<!Chars> @Nil()
    %cs1 = idr.con !idr.box<!Chars> @Cons(%next : i32, %nilc : !idr.box<!Chars>)
    %cs = idr.con !idr.box<!Chars> @Cons(%c : i32, %cs1 : !idr.box<!Chars>)
    %x = idr.constant !idr.str "x"
    %y = idr.constant !idr.str "yz"
    %nils = idr.con !idr.box<!Strs> @Nil()
    %ss1 = idr.con !idr.box<!Strs> @Cons(%y : !idr.str, %nils : !idr.box<!Strs>)
    %ss = idr.con !idr.box<!Strs> @Cons(%x : !idr.str, %ss1 : !idr.box<!Strs>)
    %w1 = idr.call @append(%n, %w0) : (i64, !idr.world) -> !idr.world
    %w2 = idr.call @cons(%c, %y, %w1) : (i32, !idr.str, !idr.world) -> !idr.world
    %w3 = idr.call @from_char(%c, %w2) : (i32, !idr.world) -> !idr.world
    %w4 = idr.call @shows(%b, %d, %w3) : (i8, f64, !idr.world) -> !idr.world
    %w5, %kept = idr.call @shared(%c, %w4) : (i32, !idr.world) -> (!idr.world, !idr.str)
    %kl = idr.str.length %kept
    %w6 = idr.io.put_sint %kl, %w5 : i64
    %w7 = idr.call @lists(%cs, %ss, %w6) : (!idr.box<!Chars>, !idr.box<!Strs>, !idr.world) -> !idr.world
    %w8 = idr.call @line(%cs, %w7) : (!idr.box<!Chars>, !idr.world) -> !idr.world
    %w9, %packed = idr.call @packed_and_kept(%cs, %w8) : (!idr.box<!Chars>, !idr.world) -> (!idr.world, !idr.str)
    %pl = idr.str.length %packed
    %w10 = idr.io.put_sint %pl, %w9 : i64
    %w11 = idr.call @constant_list(%w10) : (!idr.world) -> !idr.world
    %w12 = idr.call @nil(%w11) : (!idr.world) -> !idr.world
    %w13 = idr.call @cell(%cs, %w12) : (!idr.box<!Chars>, !idr.world) -> !idr.world
    %w14 = idr.call @cells_of_strings(%x, %y, %w13) : (!idr.str, !idr.str, !idr.world) -> !idr.world
    %w15, %l = idr.call @cell_kept(%cs, %w14) : (!idr.box<!Chars>, !idr.world) -> (!idr.world, !idr.box<!Chars>)
    %h = idr.match %l : !idr.box<!Chars> -> (i64) {
    case @Cons(%hc: i32, %ht: !idr.box<!Chars>) {
      %hw = arith.extui %hc : i32 to i64
      idr.yield %hw : i64
    }
    default(%dd: !idr.box<!Chars>) {
      %z = arith.constant 0 : i64
      idr.yield %z : i64
    }
    }
    %w16 = idr.io.put_sint %h, %w15 : i64
    %c3 = arith.constant 3 : i64
    %a = arith.remui %byte, %c3 : i64
    %w17 = idr.call @packed_in_a_region(%a, %cs, %w16) : (i64, !idr.box<!Chars>, !idr.world) -> !idr.world
    return %w17 : !idr.world
  }
}
