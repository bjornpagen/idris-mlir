// RUN: idris-mlir-opt %s --idr-defunctionalize --idr-rc --idr-lower --idr-expect=holds=lowered -o /dev/null
// RUN: awk 'BEGIN { printf "!Wide = !idr.data<\"Wide\", plain [@A("; for (i = 0; i < 256; i++) printf (i ? ", " : "") "!idr.str"; print ")]>"; print "idr.program @wide root(@build) stage(higher) {"; print "  idr.func @build(%x: !idr.str) -> !idr.box<!Wide> {"; printf "    %%v = idr.con !idr.box<!Wide>"; print "    return %v : !idr.box<!Wide>"; print "  }"; print "}" }' > %t.wide.mlir @A("; for (i = 0; i < 256; i++) printf (i ? " : "; for (i = 0; i < 256; i++) printf (i ? ", " : "") "%%x"; printf " : " : "") "!idr.str"; print ")
// RUN: idris-mlir-opt %t.wide.mlir --idr-defunctionalize --idr-rc --idr-lower '--idr-expect=holds=lowered,calls=@build:@idris_rt_cell' -o /dev/null
// RUN: awk 'BEGIN { printf "!Many = !idr.data<\"Many\", plain ["; for (i = 0; i < 65537; i++) printf (i ? ", " : "") "@C" i "()"; print "]>"; print "idr.program @many root(@last) stage(higher) {"; print "  idr.func @last() -> !idr.box<!Many> {"; print "    %v = idr.con !idr.box<!Many>"; print "    return %v : !idr.box<!Many>"; print "  }"; print "}" }' > %t.many.mlir @C65536()
// RUN: idris-mlir-opt %t.many.mlir --idr-defunctionalize --idr-rc --idr-lower --idr-expect=holds=lowered -o /dev/null
// NEEDS-ACCEPTANCE: that each program lowers, as R01's layout lifts the limits: a cell of more counted references than its header counts holds a count word after the header, and a sum of more constructors than a tag counts is a two-level sum.
// A cell's header holds its tag in 16 bits and its number of object slots
// (counted references) in 8, and no program is refused for outgrowing
// either: a cell with more counted references than the header counts
// keeps the count in a word after its header, and a sum with more
// constructors than a tag counts is a sum of groups, an outer tag picking
// the group and each group a sum a tag counts. So each of these compiles
// to the end of the lowering: a constructor of 256 strings, built; a sum
// of 65,537 constructors, its last one built; and a record of 86 records
// of three strings each, 258 counted references in one cell, which the
// layout first boxes as it must.
!Three = !idr.data<"Three", plain [@P(!idr.str, !idr.str, !idr.str)]>
!Holder = !idr.data<"Holder", plain [@H(!Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three)]>
idr.program @layout root(@root) stage(higher) {
  idr.func @hold(%x: !idr.box<!Holder>) -> !idr.box<!Holder> {
    return %x : !idr.box<!Holder>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
