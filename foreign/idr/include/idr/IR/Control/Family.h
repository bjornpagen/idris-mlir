// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The carrier of the join family's constant, which the generated code of
// the control-flow ops includes before the ops: the generator writes one
// specialization per member from the specification
// (IdrisMLIR.Spec.Control.Joins), and the C++ of the family is one template
// instantiated per member over it.
#ifndef IDR_IR_CONTROL_FAMILY_H
#define IDR_IR_CONTROL_FAMILY_H

namespace idr {

// The member's constant `tokens`: where its tokens are, which is whether
// its regions repeat.
template <typename Op>
struct JoinPointsFamily;

// The members of the family are monomorphic: one instantiation of each
// template over them per member, chosen by the member's constant.
template <typename Group>
concept JoinFamily = requires { JoinPointsFamily<Group>::tokens; };

template <JoinFamily Group>
inline constexpr auto tokensAt = JoinPointsFamily<Group>::tokens;

} // namespace idr

#endif // IDR_IR_CONTROL_FAMILY_H
