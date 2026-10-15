// RUN: %status 1 idris-mlir-opt %s -split-input-file --idr-lower -o /dev/null 2> %t.err
// RUN: FileCheck %s --check-prefix=WIDE < %t.err
// RUN: awk 'BEGIN { printf "!Many = !idr.data<\"Many\", plain ["; for (i = 0; i < 65537; i++) printf "%s@C%d()", (i ? ", " : ""), i; print "]>"; print "idr.func private @hold(%m: !idr.box<!Many>) -> !idr.box<!Many> {"; print "  return %m : !idr.box<!Many>"; print "}"; print "idr.func @Prog.main() -> i64 {"; print "  %z = arith.constant 0 : i64"; print "  return %z : i64"; print "}" }' > %t.many.mlir
// RUN: not idris-mlir-opt %t.many.mlir 2>&1 | FileCheck %s --check-prefix=MANY
// RUN: awk 'BEGIN { printf "!Most = !idr.data<\"Most\", plain ["; for (i = 0; i < 65536; i++) printf "%s@C%d()", (i ? ", " : ""), i; print "]>"; print "idr.func private @hold(%m: !idr.box<!Most>) -> !idr.box<!Most> {"; print "  return %m : !idr.box<!Most>"; print "}"; print "idr.func @Prog.main() -> i64 {"; print "  %z = arith.constant 0 : i64"; print "  return %z : i64"; print "}" }' > %t.most.mlir
// RUN: idris-mlir-opt %t.most.mlir --idr-lower -o /dev/null
// NEEDS-ACCEPTANCE: the texts of the two layout refusals, as C03 and C04 write them, and where the cell-width one is reported.
// A cell's header holds its tag in 16 bits and its number of object slots
// (counted references) in 8. What fits is lowered; what does not is
// rejected once, by name, and never written as a header whose fields run
// into each other: a box of a data type with more constructors than a tag
// can count is refused by the module's rules, when the module is read; a
// cell too wide, where the layouts are decided.
// MANY: unsupported (layout): the boxed type "Many" has 65537 constructors, and a boxed type has at most 65536
// MANY-NOT: unsupported
// WIDE-NOT: 255 counted references
// WIDE-DAG: unsupported (layout): {{.*}}@A{{.*}}256 counted references
// WIDE-DAG: unsupported (layout): {{.*}}@H{{.*}}258 counted references

// 255 counted references fit.
!Fits = !idr.data<"Fits", plain [@A(!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)]>
idr.func private @hold(%x: !idr.box<!Fits>) -> !idr.box<!Fits> {
  return %x : !idr.box<!Fits>
}

// -----

!Wide = !idr.data<"Wide", plain [@A(!idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str, !idr.str)]>
idr.func private @hold(%x: !idr.box<!Wide>) -> !idr.box<!Wide> {
  return %x : !idr.box<!Wide>
}

// -----

// An unboxed sum spreads over the cell that holds it: three counted slots
// in each of 86 fields are 258. Lowered alone, that is rejected here; in
// the pipeline, idr-defunctionalize first boxes the record "Three", and the
// cell holds 86 references.
!Three = !idr.data<"Three", plain [@P(!idr.str, !idr.str, !idr.str)]>
!Holder = !idr.data<"Holder", plain [@H(!Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three, !Three)]>
idr.func private @hold(%x: !idr.box<!Holder>) -> !idr.box<!Holder> {
  return %x : !idr.box<!Holder>
}
