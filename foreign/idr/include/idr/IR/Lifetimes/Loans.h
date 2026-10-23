// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// A loan's aliases, followed: what the function verifier's rule of loans
// and the lifetime pass's lending read alike. An idr.carrier's result is a
// bare carrier, and a bare carrier names no lifetime, so where a loan may
// go is found by following it: through upstream's view interface for a
// buffer, through bufferization's aliasing for a tensor, and through what a
// region branch forwards, each the interface upstream's own alias readers
// take. No list of ops is kept: an op says what it aliases by those
// interfaces, what it takes over by its consumption, what it adopts by its
// trait (AdoptsCarrier) or, for an op of ours, by the moves its flow edges
// declare, and what it stores by its effects. And an alias read where its
// loan cannot stand is made again there, of another loan of the holder, by
// one mechanism the lending and frames share (remakeAlias).
#ifndef IDR_IR_LIFETIMES_LOANS_H
#define IDR_IR_LIFETIMES_LOANS_H

#include "idr/IR/Flow.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/Dialect/Bufferization/IR/BufferizableOpInterface.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/Value.h"
#include "mlir/Interfaces/ViewLikeInterface.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/DenseSet.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/Twine.h"

#include <concepts>
#include <cstdint>
#include <optional>
#include <type_traits>

namespace idr::lifetimes {

// What one use of an alias of a loan does with it: an op of upstream's
// reads it (what it makes of it is followed in turn), a region branch
// forwards it (the value it becomes is followed), or it is one of the three
// ways out: returned from the function, stored as the value a write puts
// into memory, or adopted by an op of ours, which takes a reference over,
// makes one of its own of it, or moves it into what it holds or gives.
enum class LoanUse : std::uint8_t { Reads, Forwards, Returns, Stores, Adopts };

// What `use` does with an alias it is not forwarding: a terminator that
// forwards it to no successor is its function's return.
LoanUse loanUseOf(mlir::OpOperand &use);

// The options bufferization's aliasing is asked under: its defaults, one
// set for the process, since what an op aliases is the op's to say and no
// option of a loan's changes it.
const mlir::bufferization::BufferizationOptions &aliasOptions();

// Each alias a loan reaches from the uses `starts` (the uses of a carrier's
// result, or the reads of a value about to be lent), given to `onAlias`
// once, and each use of the loan, its starts among them, given to `onUse`
// once with what it does. A region branch's forwarding is read first, so a
// yield that forwards an alias within the function forwards it and only a
// return leaves.
//
// The walk's stack and the aliases it has met are its own, sized by the
// loan's aliases and dropped when it ends: an alias exists only once the
// walk finds it, so nothing numbered before could stand for one, and a
// region that runs again forwards an alias back to an argument already met,
// which the set meets once.
template <typename OnAlias, typename OnUse>
  requires std::invocable<OnAlias &, mlir::Value> &&
           std::invocable<OnUse &, mlir::OpOperand &, LoanUse>
void forEachLoanUse(llvm::ArrayRef<mlir::OpOperand *> starts, OnAlias &&onAlias, OnUse &&onUse) {
  llvm::SmallVector<mlir::OpOperand *, 8> work(starts.begin(), starts.end());
  llvm::SmallDenseSet<mlir::Value, 8> met;
  std::optional<mlir::bufferization::AnalysisState> state;
  auto reach = [&](mlir::Value alias) {
    if (!met.insert(alias).second)
      return;
    onAlias(alias);
    for (mlir::OpOperand &use : alias.getUses())
      work.push_back(&use);
  };
  while (!work.empty()) {
    mlir::OpOperand &use = *work.pop_back_val();
    mlir::Operation *user = use.getOwner();
    bool forwarded = false;
    forwardedValues(user, [&](mlir::OpOperand &operand, mlir::Value input) {
      if (&operand != &use)
        return;
      forwarded = true;
      reach(input);
    });
    if (forwarded) {
      onUse(use, LoanUse::Forwards);
      continue;
    }
    LoanUse kind = loanUseOf(use);
    onUse(use, kind);
    if (kind != LoanUse::Reads)
      continue;
    if (auto view = llvm::dyn_cast<mlir::ViewLikeOpInterface>(user);
        view && view.getViewSource() == use.get())
      reach(view.getViewDest());
    // A tensor operand's aliases are bufferization's to say, an op it does
    // not know aliasing every tensor it gives.
    if (llvm::isa<mlir::bufferization::TensorLikeType>(use.get().getType())) {
      if (!state)
        state.emplace(aliasOptions());
      for (const mlir::bufferization::AliasingValue &aliasing : state->getAliasingValues(use))
        reach(aliasing.value);
    }
  }
}

// An invariant a pass before this one promised, broken at `op`: an internal
// error, fatal in every build, naming `what` was promised, the op and where
// it stands.
[[noreturn]] void brokenAt(mlir::Operation *op, const llvm::Twine &what);

// Whether `op`, which makes a step of a loan's alias, may be made again
// elsewhere and mean what it meant: it has no effect, and upstream says it
// may run anywhere (speculation, which no effect states: a guarded op has
// no effect and runs below its guard). A loan costs nothing at run time,
// and a view of one is a function of its operands.
bool remakeable(mlir::Operation *op);

// `alias` made again before `at`, from `root` up, the originals untouched:
// `through` names, for a value of the chain, the operand by which the op
// that makes it stands on the value below. Each op of the chain is made
// again once per `again`, in order, so aliases that share steps share what
// is made, and goes to `onMade` with the original's operand it stood on by
// and the op made. The lending stands each loan where every alias it reads
// past a cut can be made again, and frames lend again only what can be,
// so an op `through` names no operand of, or one remakeable does not take,
// is an internal error naming it. The value made again for `alias`.
template <typename Through, typename OnMade>
  requires std::is_invocable_r_v<mlir::OpOperand *, Through &, mlir::Value> &&
           std::invocable<OnMade &, mlir::OpOperand &, mlir::Operation *>
mlir::Value remakeAlias(mlir::Value alias, mlir::Value root, mlir::Operation *at,
                        mlir::IRMapping &again, Through &&through, OnMade &&onMade) {
  llvm::SmallVector<mlir::OpOperand *, 4> steps;
  for (mlir::Value step = alias; step != root && !again.contains(step);) {
    mlir::OpOperand *by = through(step);
    mlir::Operation *maker =
        by ? by->getOwner()
           : (step.getDefiningOp() ? step.getDefiningOp()
                                   : llvm::cast<mlir::BlockArgument>(step).getOwner()->getParentOp());
    if (!by || !remakeable(maker))
      brokenAt(maker, "a loan's alias read where it must be made again is made by an op that "
                      "cannot be: one with an effect, one that may not run anywhere, or one "
                      "reading no one value of the loan alone");
    steps.push_back(by);
    step = by->get();
  }
  mlir::OpBuilder b(at);
  for (mlir::OpOperand *by : llvm::reverse(steps))
    onMade(*by, b.clone(*by->getOwner(), again));
  return again.lookup(alias);
}

} // namespace idr::lifetimes

#endif // IDR_IR_LIFETIMES_LOANS_H
