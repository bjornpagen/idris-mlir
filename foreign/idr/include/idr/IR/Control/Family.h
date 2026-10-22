// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The join family's constant, and the concept its C++ is written over: the
// generator writes the carrier, JoinPointsFamily, with one specialization
// per member from the specification (IdrisMLIR.Spec.Control.Joins), and the
// C++ of the family is one template instantiated per member over it.
#ifndef IDR_IR_CONTROL_FAMILY_H
#define IDR_IR_CONTROL_FAMILY_H

// The member's constant is a TokenScope, one of the dialect's enums, whose
// generated file Grades.h includes for the dialect.
#include "idr/IR/Grades.h"

// The specializations name the members, so their classes are declared by
// name before the carrier, as the ops are defined after this header.
#define GET_OP_FWD_DEFINES
#include "idr/IR/IdrOps.h.inc"

// The member's constant `tokens`: where its tokens are, which is whether its
// regions repeat.
#include "idr/IR/Generated/JoinPointsFamily.h.inc"

namespace idr {

// The members of the family are monomorphic: one instantiation of each
// template over them per member, chosen by the member's constant.
template <typename Group>
concept JoinFamily = requires { JoinPointsFamily<Group>::tokens; };

template <JoinFamily Group>
inline constexpr auto tokensAt = JoinPointsFamily<Group>::tokens;

} // namespace idr

#endif // IDR_IR_CONTROL_FAMILY_H
