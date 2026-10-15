// RUN: idris-mlir-opt %s | FileCheck %s
// RUN: idris-mlir-opt %s | idris-mlir-opt | FileCheck %s
// A grade is `!idr.q<quantity, permission, value>`, which is how the
// frontend writes every grade, and the dialect spells the common ones
// shorter: it reads either form, writes the short one where there is one
// and any other grade written out, so a printed module reads back as itself.


// The long forms of the spelled grades print as their spellings.
// CHECK-LABEL: idr.func private @spelled(
// CHECK-SAME: %{{[^:]*}}: !idr.lin<!idr.str>, %{{[^:]*}}: !idr.own<!idr.big>, %{{[^:]*}}: !idr.excl<!idr.box<!T>>, %{{[^:]*}}: !idr.world)
!T = !idr.data<"T", plain [@A()]>
idr.func private @spelled(%a0: !idr.q<one, plain, !idr.str>, %a1: !idr.q<many, own, !idr.big>, %a2: !idr.q<many, excl, !idr.box<!T>>, %a3: !idr.q<one, plain, !idr.world_carrier>) {
  idr.crash "no body"
  ub.unreachable
}

// A grade without a spelling prints written out.
// CHECK-LABEL: idr.func private @long(
// CHECK-SAME: %{{[^:]*}}: !idr.q<one, own, !idr.str>, %{{[^:]*}}: !idr.q<many, borrow, !idr.str>, %{{[^:]*}}: !idr.q<one, excl, !idr.box<!T>>)
idr.func private @long(%a0: !idr.q<one, own, !idr.str>, %a1: !idr.q<many, borrow, !idr.str>, %a2: !idr.q<one, excl, !idr.box<!T>>) {
  idr.crash "no body"
  ub.unreachable
}

// The spellings print as themselves.
// CHECK-LABEL: idr.func private @sugar(
// CHECK-SAME: %{{[^:]*}}: !idr.lin<!idr.str>, %{{[^:]*}}: !idr.own<!idr.big>, %{{[^:]*}}: !idr.excl<!idr.box<!T>>, %{{[^:]*}}: !idr.world)
idr.func private @sugar(%a0: !idr.lin<!idr.str>, %a1: !idr.own<!idr.big>, %a2: !idr.excl<!idr.box<!T>>, %a3: !idr.world) {
  idr.crash "no body"
  ub.unreachable
}
