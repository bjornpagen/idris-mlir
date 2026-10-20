// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-lower '--idr-expect=holds=lowered,calls=@root:@hold' -o /dev/null
// RUN: idris-mlir -c %s -o %t.o
// RUN: %cc %t.o -o %t
// RUN: printf 'abc\n' | %t | FileCheck %s --match-full-lines --check-prefix=HOLDER
// RUN: awk 'function wide(n, file,    i) { print "!Wide = !idr.data<\"Wide\">" > file; printf "#types = #idr.types<\"Wide\" = plain [@A(" > file; for (i = 0; i < n; i++) printf (i ? ", " : "") "!idr.str" > file; print ")]>" > file; print "idr.program @wide root(@build) stage(higher) types #types {" > file; print "  idr.func @first(%v: !idr.box<!Wide>) -> !idr.str attributes {no_inline} {" > file; print "    %f = idr.field %v : !idr.box<!Wide> @A[0] -> !idr.str" > file; print "    return %f : !idr.str" > file; print "  }" > file; print "  idr.func @last(%v: !idr.box<!Wide>) -> !idr.str attributes {no_inline} {" > file; print "    %f = idr.field %v : !idr.box<!Wide> @A[" n - 1 "] -> !idr.str" > file; print "    return %f : !idr.str" > file; print "  }" > file; print "  idr.func @build(%w: !idr.world) -> !idr.world {" > file; print "    %x, %w1 = idr.io.get_line %w" > file; print "    %y = idr.constant !idr.str \"last\"" > file; printf "    %%v = idr.con !idr.box<!Wide> @A(" > file; for (i = 0; i < n; i++) printf (i ? ", " : "") (i < n - 1 ? "%%x" : "%%y") " : !idr.str" > file; print ")" > file; print "    %f = idr.call @first(%v) : (!idr.box<!Wide>) -> !idr.str" > file; print "    %g = idr.call @last(%v) : (!idr.box<!Wide>) -> !idr.str" > file; print "    %w2 = idr.io.put_str %f, %w1" > file; print "    %w3 = idr.io.put_str %g, %w2" > file; print "    return %w3 : !idr.world" > file; print "  }" > file; print "}" > file } BEGIN { wide(255, ARGV[1]); wide(256, ARGV[2]) }' %t.wide255.mlir %t.wide256.mlir
// RUN: idris-mlir-opt %t.wide255.mlir --idr-defunctionalize --idr-rc --idr-lower '--idr-expect=holds=lowered,calls=@build:@idris_rt_cell,calls=@build:@last' -o /dev/null
// RUN: idris-mlir-opt %t.wide256.mlir --idr-defunctionalize --idr-rc --idr-lower '--idr-expect=holds=lowered,calls=@build:@idris_rt_cell,calls=@build:@last' -o /dev/null
// RUN: idris-mlir -c %t.wide255.mlir -o %t.wide255.o
// RUN: %cc %t.wide255.o -o %t.wide255
// RUN: printf 'abc\n' | %t.wide255 | FileCheck %s --match-full-lines --check-prefix=WIDE
// RUN: idris-mlir -c %t.wide256.mlir -o %t.wide256.o
// RUN: %cc %t.wide256.o -o %t.wide256
// RUN: printf 'abc\n' | %t.wide256 | FileCheck %s --match-full-lines --check-prefix=WIDE
// RUN: awk 'function many(n, file,    i) { print "!Many = !idr.data<\"Many\">" > file; printf "#types = #idr.types<\"Many\" = plain [" > file; for (i = 0; i < n; i++) printf (i ? ", " : "") "@C" i "()" > file; print "]>" > file; print "idr.program @many root(@start) stage(higher) types #types {" > file; print "  idr.func @tagOf(%v: !idr.box<!Many>) -> i64 attributes {no_inline} {" > file; print "    %g = idr.tag %v : !idr.box<!Many>" > file; print "    return %g : i64" > file; print "  }" > file; print "  idr.func @start(%w: !idr.world) -> !idr.world {" > file; print "    %v = idr.con !idr.box<!Many> @C" n - 1 "()" > file; print "    %g = idr.call @tagOf(%v) : (!idr.box<!Many>) -> i64" > file; print "    %w1 = idr.io.put_sint %g, %w : i64" > file; print "    return %w1 : !idr.world" > file; print "  }" > file; print "}" > file } BEGIN { many(65536, ARGV[1]); many(65537, ARGV[2]) }' %t.many65536.mlir %t.many65537.mlir
// RUN: idris-mlir-opt %t.many65536.mlir --idr-defunctionalize --idr-rc --idr-lower '--idr-expect=holds=lowered,calls=@start:@tagOf' -o /dev/null
// RUN: idris-mlir-opt %t.many65537.mlir --idr-defunctionalize --idr-rc --idr-lower '--idr-expect=holds=lowered,calls=@start:@tagOf' -o /dev/null
// RUN: idris-mlir -c %t.many65536.mlir -o %t.many65536.o
// RUN: %cc %t.many65536.o -o %t.many65536
// RUN: %t.many65536 | FileCheck %s --match-full-lines --check-prefix=TAG65535
// RUN: idris-mlir -c %t.many65537.mlir -o %t.many65537.o
// RUN: %cc %t.many65537.o -o %t.many65537
// RUN: %t.many65537 | FileCheck %s --match-full-lines --check-prefix=TAG65536
// A cell's header holds its tag in 16 bits and its number of object slots
// (counted references) in 8, and no program is refused for outgrowing
// either: a cell with more counted references than the header counts
// keeps the count in a word after its header, and a sum with more
// constructors than a tag counts is a sum of groups, an outer tag picking
// the group and each group a sum a tag counts. So each of these compiles
// to the end of the lowering, at each limit and one past it: a constructor
// of 255 strings and of 256, built and read; a sum of 65,536 constructors
// and of 65,537, its last one built and matched; and a record of 86
// records of three strings each, 258 counted references in one cell, which
// the layout first boxes as it must, built at run time and passed through
// a call. And each runs, reading the slot it names: compiled whole by
// idris-mlir, each wide constructor's program prints its first string, the
// line it reads, and its last, the constant "last"; the record's, its
// first record's first string, the line, and its last one's third, the
// constant "end"; and each sum's, the tag of its last constructor, one
// less than the number of them.
// HOLDER: abcend
// WIDE: abclast
// TAG65535: 65535
// TAG65536: 65536
!Three = !idr.data<"Three">
!Holder = !idr.data<"Holder">
#types = #idr.types<
  "Holder" = plain [@H(!Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three)],
  "Three" = plain [@P(!idr.str, !idr.str, !idr.str)]
>
idr.program @layout root(@root) stage(higher) types #types {
  idr.func @hold(%x: !idr.box<!Holder>) -> !idr.box<!Holder> attributes {no_inline} {
    return %x : !idr.box<!Holder>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %s, %w1 = idr.io.get_line %w
    %p = idr.con !Three @P(%s : !idr.str, %s : !idr.str, %s : !idr.str)
    %end = idr.constant !idr.str "end"
    %q = idr.con !Three @P(%s : !idr.str, %s : !idr.str, %end : !idr.str)
    %h = idr.con !idr.box<!Holder> @H(%p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %q : !Three)
    %k = idr.call @hold(%h) : (!idr.box<!Holder>) -> !idr.box<!Holder>
    %e = idr.field %k : !idr.box<!Holder> @H[0] -> !Three
    %a = idr.field %e : !Three @P[0] -> !idr.str
    %w2 = idr.io.put_str %a, %w1
    %f = idr.field %k : !idr.box<!Holder> @H[85] -> !Three
    %t = idr.field %f : !Three @P[2] -> !idr.str
    %w3 = idr.io.put_str %t, %w2
    return %w3 : !idr.world
  }
}
