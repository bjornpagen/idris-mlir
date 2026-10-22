// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-in-place: the in-place promise, decided on the program as the
// frontend wrote it, right after defunctionalization and idr-knots and
// before any pass that only makes code faster or smaller, so that no
// optimization can add or remove a refusal. A family the registry marks
// in_place promises its values are rebuilt in their own cells with no test
// at run time: a function that takes apart a value of the family bound at
// quantity 1 (a parameter, or a field a linear match binds) and builds one
// of the family from it rebuilds that cell, and every call owes the
// function a value whose own family's cells are unshared. A call that
// cannot be proved to pay is refused, `unsupported (uniqueness)`, at the
// user's call, naming the cause. The verdict is types and ops: each
// obligation the grade `unique self` (or `unique deep` where a value
// encloses the one rebuilt) on its parameter and on every value of the
// chain that pays it, and each rebuild a take at the case's entry whose
// linear token idr.token.rebuild consumes.
#ifndef IDR_TRANSFORMS_INPLACE_H
#define IDR_TRANSFORMS_INPLACE_H

#include "mlir/Pass/Pass.h"

namespace idr {

#define GEN_PASS_DECL_IDRINPLACE
#include "idr/Transforms/Passes.h.inc"

} // namespace idr

#endif // IDR_TRANSFORMS_INPLACE_H
