// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The test a literal match makes of a key, for each literal carrier of
// ours: one op, at equality, of the value and the key's constant, the
// runtime's comparison of two values of the carrier. The carrier builds it
// where the match is lowered (LiteralTypeInterface::buildKeyTest), and a
// value known while compiling is tested by the same op's one fold, so which
// comparison a key is tested by is stated here once, as the op. A word's
// key is upstream's to test (arith.cmpi), which its own model builds.
#ifndef IDR_IR_CONTROL_KEYTESTS_H
#define IDR_IR_CONTROL_KEYTESTS_H

#include "idr/IR/IdrDialect.h"

#include <optional>

namespace idr {

// The op that tests a value of `Carrier` against a key.
template <class Carrier>
struct KeyTestOf;

// A string is its key where the runtime's comparison of the two is equal.
template <>
struct KeyTestOf<StrType> {
  using Op = StrCmpOp;
};

// An Integer or a natural is its key where the runtime's comparison of the
// two is equal.
template <>
struct KeyTestOf<BigType> {
  using Op = BigCmpOp;
};
template <>
struct KeyTestOf<NatType> {
  using Op = BigCmpOp;
};

template <class Carrier>
using KeyTest = typename KeyTestOf<Carrier>::Op;

// A key test asks whether the two are one value.
inline constexpr CmpPredicate keyTestPredicate = CmpPredicate::eq;

// The key test of `Carrier` where `builder` stands: of `held`, a value of
// it read in place at its grade, and the key, a constant at that type.
template <class Carrier>
mlir::Value buildKeyTestOf(mlir::OpBuilder &builder, mlir::Location loc, mlir::Value held,
                           mlir::Attribute key) {
  mlir::Value literal = ConstantOp::create(builder, loc, held.getType(), key);
  return KeyTest<Carrier>::create(builder, loc, held, literal, keyTestPredicate);
}

// The key test of `Carrier` folded: its op's one fold of the value and the
// key, as `where` holds the two, giving the op's result of type `truth`
// (an i1) as `where` makes one; none where either is no constant `where`
// reads as the op takes it.
template <class Carrier, fold::Where W>
std::optional<typename W::Result> foldKeyTest(W &where, const typename W::Operand &held,
                                              const typename W::Operand &key, mlir::Type truth) {
  using Op = KeyTest<Carrier>;
  typename Op::Properties properties;
  properties.setPredicate(keyTestPredicate);
  return fold::evaluate<Op>(where, {held, key}, truth, properties);
}

} // namespace idr

#endif // IDR_IR_CONTROL_KEYTESTS_H
