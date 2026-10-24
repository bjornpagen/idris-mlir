// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Every call of a function becomes the member of the call family its place
// makes, read off the function's tails down from its body: what a pass
// does whose edit leaves a call where an op that holds no fact stood, so
// that no call's member says where the call no longer stands. The program
// becoming first order is one (the frontend's calls promise nothing, and an
// apply holds no fact); so is a body written back whole, a floating op made
// again wherever it is demanded, and an op erased after a call, a count, a
// read or a body inlined that gave its argument back. A pass that knows
// where each call it makes or moves stands makes that member instead.
#ifndef IDR_TRANSFORMS_OPTIMIZE_TAILS_H
#define IDR_TRANSFORMS_OPTIMIZE_TAILS_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <utility>

namespace idr::optimize {

// Whether making a function's calls the members their places make changed
// one, so what holds the standings (the program graph's rows) reads them
// again.
enum class Facts : std::uint8_t { Kept, Changed };

// Each call ends no tail but where the function's tails say it does: each
// call in tail position becomes a tail call, and every other the member a
// call that ends none is. Where each stands is read before any call is
// made again, one walk of the calls and one of the tails, so no call is
// looked for among the tails it changed.
inline Facts decideTails(FuncOp fn) {
  llvm::SmallVector<mlir::Operation *> tails = tail::sourcesOf(fn);
  llvm::SmallVector<std::pair<FunctionCallOpInterface, CallStanding>> moved;
  fn.walk([&](FunctionCallOpInterface call) {
    CallStanding standing = llvm::is_contained(tails, call.getOperation()) ? CallStanding::Tail
                                                                           : tail::offTail(call);
    if (standing != call.getStanding())
      moved.push_back({call, standing});
  });
  mlir::IRRewriter rewriter(fn.getContext());
  for (auto [call, standing] : moved)
    (void)tail::restand(rewriter, call, standing);
  return moved.empty() ? Facts::Kept : Facts::Changed;
}

} // namespace idr::optimize

#endif // IDR_TRANSFORMS_OPTIMIZE_TAILS_H
