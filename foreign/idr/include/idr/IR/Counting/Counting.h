// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What counting's ops share with the rest of the dialect: the rule for what
// a field of a built value may hold, which a cell's init, a rebuild and a
// constructor value all obey; and the size check of a recycle, which needs
// the target's layout and so runs where the program's verifier holds one.
// The ops, their types, their predicates and their directives are the
// specification's (Spec.Counting), declared by the generated headers
// IdrDialect.h includes; their hooks are lib/IR/Counting's.
#ifndef IDR_IR_COUNTING_COUNTING_H
#define IDR_IR_COUNTING_COUNTING_H

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Types.h"
#include "mlir/Support/LogicalResult.h"

#include <optional>

namespace idr {

class Layouts;

// Whether a value of `type` fills a field declared `field` of a value
// built at hold `built` (none where the built value holds no reference):
// the field's carrier, perhaps refined to fewer constructors; a value used
// once fills only a field used once, which keeps it used once; and what it
// holds is freed as a field of a counted value is (by its count, whatever
// it claims, or never, as static data), unless the built value lives in a
// lifetime, whose cells may hold views of it. So a counted cell takes no
// scoped field, and no view outlives the lifetime it lives in.
bool fillsField(mlir::Type type, mlir::Type field, std::optional<Hold> built);

// Whether `recycle` gives a cell of the size of every cell its token may
// hold, as `layouts` lays cells out on the target.
mlir::LogicalResult verifyRecycle(CellRecycleOp recycle, const Layouts &layouts);

} // namespace idr

#endif // IDR_IR_COUNTING_COUNTING_H
