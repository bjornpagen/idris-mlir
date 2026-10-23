// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
//===- TailLoops.cpp - idr-tail-loops -------------------------------------===//
//
// A function's self tail calls become one loop: a recursive join point
// whose region is the old body, each self tail call a jump back to it
// (idr::joins::loopSelf, the one construction of join points). A call
// whose fact is `tail` is in tail position by the verifier's word, so the
// jump that replaces it is a tail transfer, and nothing after it runs.
//
// The loop is an optimization over the guarantee, not the guarantee: a
// self tail call left a call is `musttail` at the lowering and grows no
// stack either. So the loop is an action a debug counter may skip.
//
// Whether the loop may run forever is what Idris proved of the function:
// a loop of code it did not prove to end begins its join region with
// idr.may_loop, whose divergence the function's derived row holds as its
// self tail calls' cycle did, and which goes with the loop wherever it is
// inlined or copied, so an unused one stays, as eager evaluation keeps it.
//
// The pass reads its own function and nothing else, and changes nothing
// outside it.
//
// A lifetime never crosses a merge, so no jump passes one: the loop reads
// the function's own lifetimes, which every self call it makes a jump
// passes unchanged. A self call that passes other lifetimes stays a tail
// call inside the loop, still in tail position through it, and is
// `musttail` at the lowering.
//
//===----------------------------------------------------------------------===//

#include "idr/Transforms/Tail.h"

#include "idr/IR/Generated/Actions.h.inc"
#include "idr/IR/Func.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Tail.h"
#include "idr/Support/Actions.h"
#include "idr/Transforms/Counting/Bound.h"
#include "idr/Transforms/Joins.h"

#include "mlir/IR/PatternMatch.h"
#include "mlir/Pass/Pass.h"
#include "llvm/ADT/STLExtras.h"

#define GEN_PASS_DEF_IDRTAILLOOPS
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::tail {
namespace {

// idr-tail-loops makes one function's self tail calls a loop; the unit is
// the function.
struct TailLoopAction : support::TaggedAction<TailLoopAction> {
  using TaggedAction::TaggedAction;
  static constexpr std::string_view tag = ::idr::actions::tailLoopsLoop;
};

// The positions of `fn`'s lifetime parameters, in order.
llvm::SmallVector<unsigned> lifetimePositions(FuncOp fn) {
  llvm::SmallVector<unsigned> positions;
  for (BlockArgument param : fn.getBody().front().getArguments())
    if (isa<LifetimeType>(param.getType()))
      positions.push_back(param.getArgNumber());
  return positions;
}

// The loop the function's body became holds, as its join region's
// parameters, every parameter of the function: those at `lifetimes` read
// the function's own instead, and no jump passes them. Then the loop states
// where each scoped value it makes lives: its results where the function's
// do, and each scoped parameter of its join region where the function's
// parameter at its position does, both read off the function's signature.
void readLifetimesFromFunction(RewriterBase &rewriter, FuncOp fn, LoopOp loop,
                               llvm::ArrayRef<unsigned> lifetimes) {
  Block &entry = fn.getBody().front();
  Region &joined = loop.getJoinRegions().front();
  unsigned tokens = static_cast<unsigned>(loop.getTokens(joined).size());
  llvm::SmallVector<JumpOp> jumps;
  for (Region &region : loop->getRegions())
    for (Operation *user : loop.getTokens(region).front().getUsers())
      jumps.push_back(cast<JumpOp>(user));
  for (unsigned position : llvm::reverse(lifetimes)) {
    BlockArgument param = joined.front().getArgument(tokens + position);
    rewriter.replaceAllUsesWith(param, entry.getArgument(position));
    for (JumpOp jump : jumps)
      rewriter.modifyOpInPlace(jump, [&] { jump.getArgsMutable().erase(position); });
    joined.front().eraseArgument(tokens + position);
  }

  LivesInAttr lives = fn.getLivesInAttr();
  llvm::SmallVector<Value> outers;
  if (lives) {
    for (const LivesIn &result : lives.getResults())
      outers.push_back(entry.getArgument(result.lifetime));
    for (BlockArgument param : loop.getParameters(joined)) {
      if (!freedBy(param.getType(), Release::Scoped))
        continue;
      // The function's parameter at this one's position, counting back the
      // lifetime parameters taken out before it.
      unsigned position = param.getArgNumber() - tokens;
      for (unsigned lifetime : lifetimes)
        position += lifetime <= position ? 1 : 0;
      outers.push_back(entry.getArgument(*lives.lifetimeOfParameter(position)));
    }
  }
  rewriter.modifyOpInPlace(loop, [&] {
    lifetimes::restateOuters(cast<StatesOutersOpInterface>(loop.getOperation()), outers);
  });
}

struct TailLoops : impl::IdrTailLoopsBase<TailLoops> {
  // The staged base finds the program and checks its stage; the pass reads
  // only its own function.
  void runOnProgram(ProgramOp) {
    FuncOp fn = getOperation();
    llvm::SmallVector<unsigned> lifetimes = lifetimePositions(fn);
    Block &entry = fn.getBody().front();
    // The self tail calls that pass the function's own lifetimes, each at
    // its own position: only those jump back.
    llvm::SmallVector<joins::Site> calls;
    fn.walk([&](CallOp call) {
      if (!tailCallOf(call) || call.getCalleeAttr().getAttr() != fn.getSymNameAttr())
        return;
      if (llvm::all_of(lifetimes, [&](unsigned position) {
            return call.getArgs()[position] == entry.getArgument(position);
          }))
        calls.push_back(joins::Site{call, 0, call.getArgs(), call.getIndexArgsAttr()});
    });
    if (calls.empty())
      return markAllAnalysesPreserved();
    IRRewriter rewriter(fn.getContext());
    const Layouts &layouts = getAnalysis<Layouts>();
    // A token the loop carries from one run of its region to the next is
    // held where the call's frame held none, so the bound is measured on
    // the loop.
    if (!support::perform<TailLoopAction>(fn, [&] {
          LoopOp loop = joins::loopSelf(rewriter, fn, calls);
          readLifetimesFromFunction(rewriter, fn, loop, lifetimes);
          fn.setFrameBound(counting::frameBound(fn, layouts));
          ++numLoops;
        }))
      return markAllAnalysesPreserved();
  }
};

} // namespace
} // namespace idr::tail
