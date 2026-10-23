// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What counting's ops share with the rest of the dialect: what an op does
// with the reference a counted operand holds, which placement and the
// linearity rule both read; the rule for what a field of a built value may
// hold, which a cell's init, a rebuild and a constructor value all obey;
// the destination of a cell's hole, which idr-trmc makes holes by; and the
// size check of a recycle, which needs the target's layout and so runs
// where the program's verifier holds one.
// The ops, their types, their predicates and their directives are the
// specification's (Spec.Counting), declared by the generated headers
// IdrDialect.h includes, with the class of the trait the ops that end an
// owner carry (Traits.h); their hooks are lib/IR/Counting's.
#ifndef IDR_IR_COUNTING_COUNTING_H
#define IDR_IR_COUNTING_COUNTING_H

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"
#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/SmallBitVector.h"

#include <cstdint>
#include <optional>

namespace idr {

class Layouts;

// What an op does with the reference a counted operand holds: keeps it,
// the operand's holder still holding it after the op (a read, a field read,
// a dup, a loan to upstream's ops); or moves it on, after which that holder
// holds none. Only a value its count frees holds a reference of its own: a
// view moved on holds none, and what receives it is a view too, so every
// other operand keeps.
enum class Reference : std::uint8_t { Kept, MovedOn };

// The one rule of what an op does with a counted operand's reference,
// which placement and the linearity rule both read, as the op declares it:
// it moves it on where it hands the value on whole (its flow moves the use
// itself into a value it makes, a part of one, a callee's parameter or a
// caller's result, upstream's region branches forwarding among it: a
// yield, a jump, a match's entering operand, a cast), or gives its
// reference up (a drop, a share, a recycle, a store's hand-over); where it
// ends the owner its first operand is (EndsOwner: a take, an unpack, the
// fused take, the test of sharing); and where it lends its first operand
// and gives it back (RunsOnceGivingBack), which no region branch forwards.
// A part moved out of a value says nothing of the value's own reference:
// an op that takes a value apart ends its owner, and a memo cell's
// exchange moves the captures out of a cell that keeps its reference.
Reference referenceAt(mlir::OpOperand &use);

// The rule at each operand of `op`, its moves read once: the operands whose
// references it moves on.
llvm::SmallBitVector movedOn(mlir::Operation *op);

// Whether a value of `type` fills a field declared `field` of a value
// built at hold `built` (none where the built value holds no reference):
// the field's carrier, perhaps refined to fewer constructors; a value used
// once fills only a field used once, which keeps it used once; and what it
// holds is freed as a field of a counted value is (by its count, whatever
// it claims, or never, as static data), unless the built value lives in a
// lifetime, whose cells may hold views of it. So a counted cell takes no
// scoped field, and no view outlives the lifetime it lives in.
bool fillsField(mlir::Type type, mlir::Type field, std::optional<Hold> built);

// The destination of hole `hole` of `cell`'s constructor: written through,
// once, with a value of the field's declared type at its grade. Failure,
// after an error at `location` when there is one, for a field the
// constructor does not have or one no destination takes.
mlir::FailureOr<DestType> destOf(std::optional<mlir::Location> location, CellType cell,
                                 std::int32_t hole);

// Whether `recycle` gives a cell of the size of every cell its token may
// hold, as `layouts` lays cells out on the target.
mlir::LogicalResult verifyRecycle(CellRecycleOp recycle, const Layouts &layouts);

} // namespace idr

#endif // IDR_IR_COUNTING_COUNTING_H
