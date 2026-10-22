// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A call's effects, from the row it carries: each ordering atom's call
// effects on its state, the atoms that only report kept as reported, and a
// write in place on each operand its callee writes through. Not a rule over
// a type: the row is the call's, which its callee's derivation writes, and
// it comes back out of the set whole.
#ifndef IDR_IR_EFFECTS_SUMMARIZED_H
#define IDR_IR_EFFECTS_SUMMARIZED_H

#include "idr/IR/Effects/Rules.h"
#include "idr/IR/Func.h"

#include "mlir/IR/Operation.h"

#include <concepts>

namespace idr::effects::detail {

// A call: the row it carries, and its copy of its callee's write part, a
// write in place it declares on each operand its callee writes through.
template <class CallOpT>
concept CarriesRow = HoldsWritePart<CallOpT> && requires(CallOpT call) {
  { call.getRow() } -> std::convertible_to<Row>;
};

// A call's set: each ordering atom's call effects on its state, the atoms
// that only report kept as reported, and a write in place for an operand
// its callee writes through. Its row comes back out of the set whole.
template <CarriesRow OpT>
EffectSet rowSet(OpT op) {
  EffectSet set;
  Row row = op.getRow();
  for (Atom atom : allOf<Atom>())
    if (row.contains(atom))
      for (Kind kind : allOf<Kind>())
        if (atomCallKinds[atom].contains(kind))
          set.add(kind, atomState[atom]);
  set.reported = row & reportsOnly;
  ::idr::forEachWritten(op, [&](mlir::OpOperand &) { set.add(Kind::Write, ResourceId::Contents); });
  return set;
}

template <CarriesRow OpT>
void emitRow(OpT op, Instances &effects) {
  Row row = op.getRow();
  for (Atom atom : allOf<Atom>())
    if (row.contains(atom))
      emitKinds(effects, atomCallKinds[atom], atomState[atom], nullptr);
  ::idr::forEachWritten(op, [&](mlir::OpOperand &operand) {
    effects.emplace_back(effect<Kind::Write>(), &operand, resource<ResourceId::Contents>());
  });
}

// Every atom's call effects and every atom that only reports: the most a
// call may declare.
inline constexpr EffectSet anyRow = [] {
  EffectSet set;
  for (Atom atom : allOf<Atom>())
    for (Kind kind : allOf<Kind>())
      if (atomCallKinds[atom].contains(kind))
        set.add(kind, atomState[atom]);
  set.reported = reportsOnly;
  set.add(Kind::Write, ResourceId::Contents);
  return set;
}();

} // namespace idr::effects::detail

#endif // IDR_IR_EFFECTS_SUMMARIZED_H
