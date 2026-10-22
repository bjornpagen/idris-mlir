// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The traits of this area's ops that the specification names and a rule
// reads: a builder whose string is never empty (Spec.Ops.Strings), which a
// guard that a string is not empty folds away on (idr/IR/Ops/Rules.h). The
// generated ops name it as a base, so the dialect's header includes this
// before them.
#ifndef IDR_IR_OPS_TRAITS_H
#define IDR_IR_OPS_TRAITS_H

#include "mlir/IR/OpDefinition.h"

namespace idr {

// A builder whose string has a character at least: one built with a
// character or a number in it. A marker the NeverEmptyString rule reads.
template <typename ConcreteType>
class NeverEmpty : public mlir::OpTrait::TraitBase<ConcreteType, NeverEmpty> {};

} // namespace idr

#endif // IDR_IR_OPS_TRAITS_H
