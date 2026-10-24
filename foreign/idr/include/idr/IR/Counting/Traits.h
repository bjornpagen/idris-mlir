// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The trait counting's ops that end an owner are built on, which the
// specification declares (Spec.Counting) and the dialect's header includes
// before the generated ops, so it sees nothing generated.
#ifndef IDR_IR_COUNTING_TRAITS_H
#define IDR_IR_COUNTING_TRAITS_H

#include "mlir/IR/OpDefinition.h"

namespace idr {

// An op that ends the owner its first operand is (`idr.count.drop`,
// `idr.count.take`, `idr.count.take_open`, `idr.count.take_into`,
// `idr.count.match_unique`, `idr.count.unpack`): it gives up the value's
// reference, or moves its cell into a token and its fields out, each a
// value of its own, or a value in place's fields out. It reads none of the fields, so the linearity rule
// counts such a use as the cell's alone, beside the field reads; and it
// moves the value's reference on, which the one rule of what an op does
// with a reference reads (Counting.h), the fused take's among them, which
// states no flow. Both ask for the trait, so no op is named.
template <typename ConcreteType>
class EndsOwner : public mlir::OpTrait::TraitBase<ConcreteType, EndsOwner> {};

} // namespace idr

#endif // IDR_IR_COUNTING_TRAITS_H
