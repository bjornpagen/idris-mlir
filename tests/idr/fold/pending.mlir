// RUN: idris-mlir-opt %s --canonicalize --idr-expect=holds=returns=@direct:_/_,reads-fields=@direct,returns=@through_match:_/_,matches-nothing=@through_match,reads-fields=@through_match,returns=@at_grade:_,reads-fields=@at_grade -o /dev/null
// NEEDS-ACCEPTANCE: the destination results of idr.con with a hole, and that canonicalize folds the fields given and keeps the read of the hole.
// NEEDS-ACCEPTANCE: syntax swept to the data-type-first form
// A field a constructor is built without, a hole, has no value until it is
// written through the destination the constructor gives for it (the one
// idr-trmc writes after the constructor is built), so a read of it folds
// to nothing, however the field is read: directly, through a match whose
// taken region is known, or at another grade. The read stays a read of the
// cell; the fields the constructor was built with fold as ever.
!List = !idr.data<"List", list [@Nil() nil, @Cons(i64, !idr.box<!idr.data<"List">>) cons]>
!LList = !idr.data<"LList", list [@LNil() nil, @LCons(i64, !idr.lin<!idr.box<!idr.data<"LList">>>) cons]>
idr.program @pending root(@root) stage(first) {
  idr.func @direct(%x: i64) -> (i64, !idr.box<!List>) {
    %c, %d = idr.con !idr.box<!List> @Cons(%x : i64, dest)
    %h = idr.field %c : !idr.box<!List> @Cons[0] -> i64
    %t = idr.field %c : !idr.box<!List> @Cons[1] -> !idr.box<!List>
    return %h, %t : i64, !idr.box<!List>
  }

  // The match's taken region is known, so the region replaces it and its
  // arguments become reads of the constructor's fields.
  idr.func @through_match(%x: i64) -> (i64, !idr.box<!List>) {
    %c, %d = idr.con !idr.box<!List> @Cons(%x : i64, dest)
    %r:2 = idr.match %c : !idr.box<!List> -> (i64, !idr.box<!List>) {
    case @Nil() {
      %zero = arith.constant 0 : i64
      %nil = idr.constant #idr.con<!List, @Nil, []> : !idr.box<!List>
      idr.yield %zero, %nil : i64, !idr.box<!List>
    }
    case @Cons(%h: i64, %t: !idr.box<!List>) {
      idr.yield %h, %t : i64, !idr.box<!List>
    }
    }
    return %r#0, %r#1 : i64, !idr.box<!List>
  }

  // A linear field read once moves out of the constructor into its read,
  // used out of its grade; a pending one has nothing to move.
  idr.func @at_grade(%x: i64) -> !idr.box<!LList> {
    %c, %d = idr.con !idr.box<!LList> @LCons(%x : i64, dest)
    %t = idr.field %c : !idr.box<!LList> @LCons[1] -> !idr.box<!LList>
    return %t : !idr.box<!LList>
  }
  // The program's root, which the functions above are no part of.
  idr.func @root() -> i64 {
    %zero = arith.constant 0 : i64
    return %zero : i64
  }
}
