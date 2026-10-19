// RUN: idris-mlir-opt %s | FileCheck %s
// RUN: idris-mlir-opt %s | idris-mlir-opt | FileCheck %s
// A grade is `!idr.q<quantity, permission, value>`, which is how the
// frontend writes every grade, and the dialect spells the common ones
// shorter: it reads either form, writes the short one where there is one
// and any other grade written out, so a printed module reads back as
// itself. A grade is a type, printed as one wherever it stands; these are
// declarations, so no stage's rule on which grades a program holds is
// read.
!T = !idr.data<"T", plain [@A()]>

// The long forms of the spelled grades print as their spellings.
// CHECK: func.func private @spelled(!idr.lin<!idr.str>, !idr.own<!idr.big>, !idr.excl<!idr.box<!T>>)
func.func private @spelled(!idr.q<one, plain, !idr.str>, !idr.q<many, own, !idr.big>, !idr.q<many, excl, !idr.box<!T>>)

// A grade without a spelling prints written out.
// CHECK: func.func private @long(!idr.q<one, own, !idr.str>, !idr.q<many, borrow, !idr.str>, !idr.q<one, excl, !idr.box<!T>>)
func.func private @long(!idr.q<one, own, !idr.str>, !idr.q<many, borrow, !idr.str>, !idr.q<one, excl, !idr.box<!T>>)

// The spellings print as themselves, and the world, a type of its own,
// takes no grade.
// CHECK: func.func private @sugar(!idr.lin<!idr.str>, !idr.own<!idr.big>, !idr.excl<!idr.box<!T>>, !idr.world)
func.func private @sugar(!idr.lin<!idr.str>, !idr.own<!idr.big>, !idr.excl<!idr.box<!T>>, !idr.world)
