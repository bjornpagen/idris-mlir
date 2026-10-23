// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every call of a function takes the fact its place gives it, read off the
// function's tails down from its body: what a pass writes whose edit leaves
// a call where an op that holds no fact stood, so that no fact it holds
// says where the call now stands. The program becoming first order is one
// (the frontend's calls promise nothing, and an apply holds no fact); so is
// a body written back whole, a floating op made again wherever it is
// demanded, and an op erased after a call, a count, a read or a body
// inlined that gave its argument back. A pass that knows where each call
// it makes or moves stands writes that instead.
#ifndef IDR_TRANSFORMS_OPTIMIZE_TAILS_H
#define IDR_TRANSFORMS_OPTIMIZE_TAILS_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"

#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <utility>

namespace idr::optimize {

// Whether writing a function's calls changed a fact, so what holds the
// facts (the program graph's rows) reads them again.
enum class Facts : std::uint8_t { Kept, Changed };

// Each call ends no tail but where the function's tails say it does: every
// call first takes the fact of a call that ends none, then each call in
// tail position is a tail call. One walk of the calls and one of the
// tails, so no call is looked for among the tails.
inline Facts decideTails(FuncOp fn) {
  llvm::SmallVector<std::pair<CallOp, TailKind>> had;
  fn.walk([&](CallOp call) {
    had.push_back({call, call.getTailKind()});
    call.setTailKind(tail::withContext(call));
  });
  for (mlir::Operation *source : tail::sourcesOf(fn))
    if (auto call = llvm::dyn_cast<CallOp>(source))
      call.setTailKind(TailKind::tail);
  return llvm::any_of(had, [](std::pair<CallOp, TailKind> was) {
           return was.first.getTailKind() != was.second;
         })
             ? Facts::Changed
             : Facts::Kept;
}

} // namespace idr::optimize

#endif // IDR_TRANSFORMS_OPTIMIZE_TAILS_H
