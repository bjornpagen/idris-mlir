// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Each guard's condition, written once over where its operands' values come
// from (a place a constant lives, fold::Where): the attribute fold asks it of
// the constants ops hold, and the e-graph of its own values, whether an op
// held them or the graph computed them. An integer is read as the one value
// the place knows, and decides as words do, exactly; failing that, its
// interval decides, soundly; a string, a Double or a big past the small range
// is read as the runtime holds it. Each reading's condition is one meaning of
// Numeric/Inline.h, or the runtime's own function, defined once in
// OpsChecks.cpp; these templates only read the place. IdrDialect.h includes
// this after the op classes that declare `decide`.
#ifndef IDR_IR_OPS_GUARDS_H
#define IDR_IR_OPS_GUARDS_H

#include "idr/IR/Fold.h"
#include "idr/IR/Numeric/Intervals.h"

#include "mlir/Interfaces/InferIntRangeInterface.h"
#include "llvm/ADT/APInt.h"
#include "llvm/ADT/ArrayRef.h"

#include <cstdint>
#include <optional>

namespace idr::guards {

// A divisor: zero or not, of the one integer it is (a word, or a big in the
// small range, the runtime's word); of a big past the small range, by the
// runtime's comparison with 0; or of its interval, unknown where that is of
// no width, upstream's mark of a value no interval states.
numeric::Known nonzero(const llvm::APInt &value);
numeric::Known nonzero(idris_rt_big value);
numeric::Known nonzero(const mlir::ConstantIntRanges &range);

// The count of a string's characters, its str.length's function.
std::int64_t lengthOf(const idris_rt_str *str);

// An index at least 0 and below a length: of its one value, or of its
// interval, unknown where that is of no width.
numeric::Known inBounds(const llvm::APInt &index, std::int64_t length);
numeric::Known inBounds(const mlir::ConstantIntRanges &index, std::int64_t length);

// A length of at least one character.
numeric::Known nonempty(std::int64_t length);

// A Double neither infinite nor NaN: the condition over its bits.
numeric::Known finite(double value);

// The bytes [offset, offset + count) of something of `size` bytes: of the
// three values, or of their intervals, unknown where one is of no width.
numeric::Known inRange(const llvm::APInt &offset, const llvm::APInt &count,
                       const llvm::APInt &size);
numeric::Known inRange(const mlir::ConstantIntRanges &offset,
                       const mlir::ConstantIntRanges &count, const mlir::ConstantIntRanges &size);

} // namespace idr::guards

namespace idr {

template <fold::Where W>
numeric::Known CheckNonzeroOp::decide(W &where, llvm::ArrayRef<mlir::ConstantIntRanges> ranges,
                                      llvm::ArrayRef<typename W::Operand> constants) {
  if (std::optional<llvm::APInt> value = where.integerOf(constants[0]))
    return guards::nonzero(*value);
  if (std::optional<idris_rt_big> big = where.bigOf(constants[0]))
    return guards::nonzero(*big);
  return guards::nonzero(ranges[0]);
}

// The index against the length of a constant string; an array's length is
// no value of a place, and stays unknown.
template <fold::Where W>
numeric::Known CheckInBoundsOp::decide(W &where, llvm::ArrayRef<mlir::ConstantIntRanges> ranges,
                                       llvm::ArrayRef<typename W::Operand> constants) {
  std::optional<const idris_rt_str *> indexed = where.strOf(constants[1]);
  if (!indexed)
    return numeric::Known::Unknown;
  std::int64_t length = guards::lengthOf(*indexed);
  if (std::optional<llvm::APInt> index = where.integerOf(constants[0]))
    return guards::inBounds(*index, length);
  return guards::inBounds(ranges[0], length);
}

// A string and a Double have no interval: only a constant decides them.
template <fold::Where W>
numeric::Known CheckNonemptyOp::decide(W &where, llvm::ArrayRef<mlir::ConstantIntRanges>,
                                       llvm::ArrayRef<typename W::Operand> constants) {
  std::optional<const idris_rt_str *> str = where.strOf(constants[0]);
  return str ? guards::nonempty(guards::lengthOf(*str)) : numeric::Known::Unknown;
}

template <fold::Where W>
numeric::Known CheckFiniteOp::decide(W &where, llvm::ArrayRef<mlir::ConstantIntRanges>,
                                     llvm::ArrayRef<typename W::Operand> constants) {
  std::optional<double> value = where.realOf(constants[0]);
  return value ? guards::finite(*value) : numeric::Known::Unknown;
}

template <fold::Where W>
numeric::Known CheckRangeOp::decide(W &where, llvm::ArrayRef<mlir::ConstantIntRanges> ranges,
                                    llvm::ArrayRef<typename W::Operand> constants) {
  std::optional<llvm::APInt> offset = where.integerOf(constants[0]);
  std::optional<llvm::APInt> count = where.integerOf(constants[1]);
  std::optional<llvm::APInt> size = where.integerOf(constants[2]);
  if (offset && count && size)
    return guards::inRange(*offset, *count, *size);
  return guards::inRange(ranges[0], ranges[1], ranges[2]);
}

// What a handle's slot holds is the run's own state, but a handle that is
// one value is one the program wrote, which never holds a string: the
// program's constant handles are null and the standard streams, and every
// handle that holds a string is one the runtime gave at run time.
template <fold::Where W>
numeric::Known CheckHoldsStringOp::decide(W &where, llvm::ArrayRef<mlir::ConstantIntRanges>,
                                          llvm::ArrayRef<typename W::Operand> constants) {
  return where.integerOf(constants[0]) ? numeric::Known::Fails : numeric::Known::Unknown;
}

} // namespace idr

#endif // IDR_IR_OPS_GUARDS_H
