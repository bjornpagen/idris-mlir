// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The call family's constant, and the concept its C++ is written over: the
// generator writes the carrier, CallsFamily, with one specialization per
// member from the specification (IdrisMLIR.Spec.Functions.Tail), so where a
// call stands is which member it is, a constant of its class, and no
// attribute holds it. A reader of every call asks FunctionCallOpInterface,
// whose standing is this constant; a definition shared by the members is
// one template instantiated per member over it.
#ifndef IDR_IR_CALLS_H
#define IDR_IR_CALLS_H

// The member's constant is a CallStanding, one of the dialect's enums,
// whose generated file Grades.h includes for the dialect.
#include "idr/IR/Grades.h"

// The specializations name the members, so their classes are declared by
// name before the carrier, as the ops are defined after this header.
#define GET_OP_FWD_DEFINES
#include "idr/IR/IdrOps.h.inc"

// The member's constant `standing`: where a call of it stands.
#include "idr/IR/Generated/CallsFamily.h.inc"

#include "llvm/Support/ErrorHandling.h"

namespace idr {

// The members of the family are monomorphic: one instantiation of each
// template over them per member, chosen by the member's constant.
template <typename Call>
concept CallFamily = requires { CallsFamily<Call>::standing; };

template <CallFamily Call>
inline constexpr CallStanding standingOf = CallsFamily<Call>::standing;

// The standing FunctionCallOpInterface answers, its default for each
// member: the member's constant.
template <typename Op>
CallStanding callStandingOf(Op) {
  return CallsFamily<Op>::standing;
}

// Whether a call of `standing` returns to its caller, which goes on after
// it, rather than being its caller's last act: a tail call is a jump, and a
// self call modulo a context fills its hole as its last act. The one
// meaning of a standing for what may follow a call: a reader of a standing
// held apart from its call, as a row of the program graph holds one, asks
// it here.
constexpr bool returnsToCaller(CallStanding standing) {
  switch (standing) {
  case CallStanding::Returns:
    return true;
  case CallStanding::Tail:
  case CallStanding::ModuloContext:
    return false;
  }
  llvm_unreachable("a standing of no case");
}

} // namespace idr

#endif // IDR_IR_CALLS_H
