// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every call of a function takes the tail fact its place gives it, by the
// one definition of tail position: what a pass of the optimizer's that
// made calls, moved one, changed which function one calls, or erased an op
// after one writes before anything reads the facts again.
#ifndef IDR_TRANSFORMS_OPTIMIZE_TAILS_H
#define IDR_TRANSFORMS_OPTIMIZE_TAILS_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"

#include <cstdint>

namespace idr::optimize {

// Whether deciding a function's calls changed a fact, so what holds the
// facts (the program graph's rows) reads them again.
enum class Facts : std::uint8_t { Kept, Changed };

inline Facts decideTails(FuncOp fn) {
  Facts facts = Facts::Kept;
  fn.walk([&](CallOp call) {
    TailKind kind = tail::decide(call);
    if (kind == call.getTailKind())
      return;
    call.setTailKind(kind);
    facts = Facts::Changed;
  });
  return facts;
}

} // namespace idr::optimize

#endif // IDR_TRANSFORMS_OPTIMIZE_TAILS_H
