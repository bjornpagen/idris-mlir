// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What counting's ops share with the rest of the dialect: what an op does
// with the reference a counted operand holds, which placement and the
// linearity rule both read; the rule for what a field of a built value may
// hold, which a cell's init, a rebuild and a constructor value all obey;
// the destination of a cell's hole, which idr-trmc makes holes by; the
// size check of a recycle, which needs the target's layout and so runs
// where the program's verifier holds one; and what the two takes of a
// value out of its cell share, which their flow and the in-place rebuild
// read.
// The ops, their types, their predicates and their directives are the
// specification's (Spec.Counting), declared by the generated headers
// IdrDialect.h includes, with the class of the trait the ops that end an
// owner carry (Traits.h); their hooks are lib/IR/Counting's.
#ifndef IDR_IR_COUNTING_COUNTING_H
#define IDR_IR_COUNTING_COUNTING_H

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/Location.h"
#include "mlir/IR/Operation.h"
#include "mlir/IR/Types.h"
#include "mlir/Support/LogicalResult.h"
#include "llvm/ADT/SmallBitVector.h"

#include <concepts>
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
// A part an op moves out of a value it takes over moves the value's
// reference on with it (a take's fields, a cell's elements put in a
// buffer's slots); a part read out of a value the op only reads (a memo
// cell's captures, an element taken out of a buffer that keeps its
// reference) moves none.
Reference referenceAt(mlir::OpOperand &use);

// The rule at each operand of `op`, its moves read once: the operands whose
// references it moves on.
llvm::SmallBitVector movedOn(mlir::Operation *op);

// What the rule reads off `op` alone, before it asks what each operand
// holds: the operands whose reference it would move on, were it one of
// their own. movedOn keeps those that hold one; a pass that puts a value
// holding none (a small big, static) where one of its own stood asks it of
// the uses that value takes over, each of which would have moved that
// reference on.
llvm::SmallBitVector movesOf(mlir::Operation *op);

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

// An op that takes a value out of its cell (idr.count.take, and the take
// before bufferization that opens the arrays the cell holds,
// idr.count.take_open): built of the value alone, its results inferred, it
// gives the cell's token and a result per field.
template <typename Op>
concept TakesOutOfCell =
    requires(Op op, mlir::OpBuilder &builder, mlir::Location loc, mlir::Value value) {
      { Op::create(builder, loc, value) } -> std::same_as<Op>;
      { op.getValueMutable() } -> std::same_as<mlir::OpOperand &>;
      { op.getDataType() } -> std::same_as<DataType>;
      { op.getTag() } -> std::same_as<Tag>;
      { op.getToken() } -> std::convertible_to<mlir::Value>;
      { op.getFields() } -> std::convertible_to<mlir::ValueRange>;
    };

} // namespace idr

#endif // IDR_IR_COUNTING_COUNTING_H
