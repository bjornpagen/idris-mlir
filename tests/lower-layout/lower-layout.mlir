// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-lower '--idr-expect=holds=lowered,calls=@root:@hold' -o /dev/null
// RUN: awk 'BEGIN { printf "!Wide = !idr.data<\"Wide\", plain [@A("; for (i = 0; i < 256; i++) printf (i ? ", " : "") "!idr.str"; print ")]>"; print "idr.program @wide root(@build) stage(higher) {"; print "  idr.func @last(%v: !idr.box<!Wide>) -> !idr.str attributes {no_inline} {"; print "    %f = idr.field %v : !idr.box<!Wide> @A[255] -> !idr.str"; print "    return %f : !idr.str"; print "  }"; print "  idr.func @build(%w: !idr.world) -> !idr.world {"; print "    %x, %w1 = idr.io.get_line %w"; printf "    %%v = idr.con !idr.box<!Wide> @A("; for (i = 0; i < 256; i++) printf (i ? ", " : "") "%%x : !idr.str"; print ")"; print "    %f = idr.call @last(%v) : (!idr.box<!Wide>) -> !idr.str"; print "    %w2 = idr.io.put_str %f, %w1"; print "    return %w2 : !idr.world"; print "  }"; print "}" }' > %t.wide.mlir
// RUN: idris-mlir-opt %t.wide.mlir --idr-defunctionalize --idr-rc --idr-lower '--idr-expect=holds=lowered,calls=@build:@idris_rt_cell,calls=@build:@last' -o /dev/null
// RUN: awk 'BEGIN { printf "!Many = !idr.data<\"Many\", plain ["; for (i = 0; i < 65537; i++) printf (i ? ", " : "") "@C" i "()"; print "]>"; print "idr.program @many root(@main) stage(higher) {"; print "  idr.func @tagOf(%v: !idr.box<!Many>) -> i64 attributes {no_inline} {"; print "    %g = idr.tag %v : !idr.box<!Many>"; print "    return %g : i64"; print "  }"; print "  idr.func @main(%w: !idr.world) -> !idr.world {"; print "    %v = idr.con !idr.box<!Many> @C65536()"; print "    %g = idr.call @tagOf(%v) : (!idr.box<!Many>) -> i64"; print "    %w1 = idr.io.put_sint %g, %w : i64"; print "    return %w1 : !idr.world"; print "  }"; print "}" }' > %t.many.mlir
// RUN: idris-mlir-opt %t.many.mlir --idr-defunctionalize --idr-rc --idr-lower '--idr-expect=holds=lowered,calls=@main:@tagOf' -o /dev/null
// A cell's header holds its tag in 16 bits and its number of object slots
// (counted references) in 8, and no program is refused for outgrowing
// either: a cell with more counted references than the header counts
// keeps the count in a word after its header, and a sum with more
// constructors than a tag counts is a sum of groups, an outer tag picking
// the group and each group a sum a tag counts. So each of these compiles
// to the end of the lowering: a constructor of 256 strings, built and
// read; a sum of 65,537 constructors, its last one built and matched; and
// a record of 86 records
// of three strings each, 258 counted references in one cell, which the
// layout first boxes as it must, built at run time and passed through a
// call.
!Three = !idr.data<"Three", plain [@P(!idr.str, !idr.str, !idr.str)]>
!Holder = !idr.data<"Holder", plain [@H(!Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three)]>
idr.program @layout root(@root) stage(higher) {
  idr.func @hold(%x: !idr.box<!Holder>) -> !idr.box<!Holder> attributes {no_inline} {
    return %x : !idr.box<!Holder>
  }
  idr.func @root(%w: !idr.world) -> !idr.world {
    %s, %w1 = idr.io.get_line %w
    %p = idr.con !Three @P(%s : !idr.str, %s : !idr.str, %s : !idr.str)
    %h = idr.con !idr.box<!Holder> @H(%p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three, %p : !Three)
    %k = idr.call @hold(%h) : (!idr.box<!Holder>) -> !idr.box<!Holder>
    %f = idr.field %k : !idr.box<!Holder> @H[85] -> !Three
    %t = idr.field %f : !Three @P[2] -> !idr.str
    %w2 = idr.io.put_str %t, %w1
    return %w2 : !idr.world
  }
}
