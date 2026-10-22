// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The passes that decide, from the program as written, which values are
// rebuilt or written in place, and the ownership passes beside them:
//
// idr-in-place: the in-place promise, decided on the program as the
// frontend wrote it, right after defunctionalization and idr-knots and
// before any pass that only makes code faster or smaller, so that no
// optimization can add or remove a refusal. A family the registry marks
// in_place promises its values are rebuilt in their own cells with no test
// at run time: a function that takes apart a value of the family bound at
// quantity 1 (a parameter, or a field a linear match binds) and builds one
// of the family from it rebuilds that cell, and every call owes the
// function what the family's promise asks: its own cells unshared (`unique
// self`, which covers the own cells of an in-place field, never its
// elements), or everything it reaches where one of them holds a buffer
// (`unique deep`), read off the family's declaration. Such a family's
// values carry the promise by construction, so a parameter of it bound at
// quantity 1 is owed it at the boundary, whatever its body does. A call
// that cannot be proved to pay is refused, `unsupported (uniqueness)`, at
// the user's call, naming the cause. The verdict is types and ops: each
// obligation its grade on its parameter and on every value of the chain
// that pays it (a record that holds the value rebuilt owes it too), and
// each rebuild a take at the case's entry whose linear token
// idr.token.rebuild consumes; then the local rule carries each claim into
// what its value is taken or read into, so bufferization reads a
// parameter's claim on the buffer its cell holds.
//
// idr-unique-results: the local rule of exclusivity, before bufferization
// reads the grades. A value is unique where it is fresh (a constructor's,
// a recycled cell's, or a call's result whose signature says so) or taken
// or read at a linear position from one that is, and it flows only through
// linear positions (Analysis/Ownership/Local.h); each result's claim in its
// function's type is derived from its returning paths over the call
// graph's components, callees first, as rows are, a path that ends the run
// giving nothing. The claims are written into the types, each call's
// results its callee's again, and wherever a value now claiming more meets
// a position that takes less, it is shared into it. idr-in-place runs the
// same rule after it grades (Transforms/InPlace/Unique.h).
//
// idr-knots refuses a reference knot counting could never free
// (Transforms/Ownership/Knots.cpp); idr-rc-exclusive commits the
// exclusivity marking, which covers what the local rule does not prove
// (Analysis/Ownership.h).
#ifndef IDR_TRANSFORMS_INPLACE_H
#define IDR_TRANSFORMS_INPLACE_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRINPLACE
#define GEN_PASS_DECL_IDRUNIQUERESULTS
#define GEN_PASS_DECL_IDRKNOTS
#define GEN_PASS_DECL_IDRRCEXCLUSIVE
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_INPLACE_H
