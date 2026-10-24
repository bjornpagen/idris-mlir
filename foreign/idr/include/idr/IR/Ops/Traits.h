// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The traits of this area's ops that the specification names: a builder
// whose string is never empty (Spec.Ops.Strings), which a guard that a
// string is not empty folds away on (idr/IR/Ops/Rules.h); an op with no
// runtime form (Spec.Ops.Bigs), which the lowering lowers to its operand;
// and an op that leaves a natural as it is (Spec.Ops.Bigs), whose narrowed
// form is its operand's word where nothing is negative. The generated ops
// name them as bases, so the dialect's header includes this before them.
#ifndef IDR_IR_OPS_TRAITS_H
#define IDR_IR_OPS_TRAITS_H

#include "mlir/IR/OpDefinition.h"

namespace idr {

// A builder whose string has a character at least: one built with a
// character or a number in it. A marker the NeverEmptyString rule reads.
template <typename ConcreteType>
class NeverEmpty : public mlir::OpTrait::TraitBase<ConcreteType, NeverEmpty> {};

// An op whose result is its first operand's word at run time, under
// another type (a natural as an Integer): idr-lower gives the result the
// operand's components, by one pattern for every op with the trait.
template <typename ConcreteType>
class NoRuntimeForm : public mlir::OpTrait::TraitBase<ConcreteType, NoRuntimeForm> {};

// An op whose result is its first operand wherever that operand is not
// negative (an Integer made a natural): idr-narrow takes the operand's word
// as it is where nothing the op takes or gives is negative.
template <typename ConcreteType>
class LeavesNaturals : public mlir::OpTrait::TraitBase<ConcreteType, LeavesNaturals> {};

} // namespace idr

#endif // IDR_IR_OPS_TRAITS_H
