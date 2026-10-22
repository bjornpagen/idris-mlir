// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What LLVM is told of a function, from its row: one function over the
// specification's table of what each atom touches and withholds, so what
// the compiler knows of effects reaches LLVM through one place. Every
// location is at least read and a write is a read and a write, so LLVM is
// never told a call touches no memory (reuse rebuilds a cell under the same
// pointer) or writes without reading (a first read would be poison).
#ifndef IDR_IR_EFFECTS_LLVM_H
#define IDR_IR_EFFECTS_LLVM_H

#include "idr/IR/Effects/Vocabulary.h"

namespace idr::effects {

using Location = ::idr::MemoryLocation;
using Access = ::idr::MemoryAccess;
using Attribute = ::idr::FunctionAttribute;

// A function's facts for LLVM: per location how it may touch it, and the
// attributes its row withholds; it is told every other one.
struct Told {
  EnumArray<Location, Access> memory{};
  EnumSet<Attribute> withheld;

  friend constexpr bool operator==(const Told &, const Told &) = default;
};

// What LLVM is told of a function whose row is `row`.
constexpr Told told(Row row) {
  Told facts;
  for (Location location : allOf<Location>())
    facts.memory[location] = Access::ReadOnly;
  for (Atom atom : allOf<Atom>()) {
    if (!row.contains(atom))
      continue;
    for (Location location : allOf<Location>())
      if (atomWrites[atom].contains(location))
        facts.memory[location] = Access::ReadWrite;
    facts.withheld = facts.withheld | atomWithholds[atom];
  }
  return facts;
}

// The facts of a function that also writes through an exclusive owned
// parameter: that argument's memory, and nothing else.
constexpr Told withParameterWrite(Told facts) {
  for (Location location : allOf<Location>())
    if (parameterAccess[location] == Access::ReadWrite)
      facts.memory[location] = Access::ReadWrite;
  return facts;
}

} // namespace idr::effects

#endif // IDR_IR_EFFECTS_LLVM_H
