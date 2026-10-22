// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-reuse: a dead cell turned into a construction of its size, guided
// by the drops placement placed, which say exactly where a cell may become
// free; so no cell is held longer than placement held it, and no reuse is
// decided on code not yet written.
//
// A source is a take that frees its emptied cell (its token freed right
// after it), or a drop of a value whose type fixes a constructor with a
// cell, which can become such a take; a sink is the source of a new cell of
// the same size. Two walks per function, over its regions:
//   - backward, the demand: the most sinks of each size on any path ahead
//     until the function's tokens die (a return, a call in tail position, a
//     jump, the end of the process); a region that may run many times
//     takes no token from outside it;
//   - forward, the assignment: a source whose token some path ahead can use
//     keeps it, and a sink recycles the best token of its size by one total
//     order (a token the type proves unique, then one of the sink's own
//     constructor, then the earliest), never a token no path ahead needs.
// The forward walk meets the points the backward walk measured in exactly
// the reverse order, so each demand is read back off one trail, with no
// table keyed by an op.
//
// Across a match's rejoin a token leaves as a result of the match, as many
// of each size as every region that rejoins holds and the code after it can
// use; the rest are freed where they end. A token is freed before a return,
// a call in tail position and a jump, and passes a call that is not in tail
// position, held by its frame. A take whose token one recycle in its own
// block consumes fuses with it into count.take_into, so the cell is given on
// with no token in between.
//
// The in-place rule decided each rebuild before counting: a rebuild is a
// token the in-place check made, consumed by token.rebuild, which this walk
// lowers into the recycle of that token and the init of its fields. The
// walk never pairs a promised cell; the promise is the program's.
//
// Every token's span is decided here, so the function's frame bound, the
// most bytes it holds dead where memory may be acquired (its tokens' cells
// and what the owners it lends past their last use reach), is measured here
// on the function as reuse leaves it, its drops already the takes they
// became (Bound.cpp), and kept on the function.
#include "idr/Transforms/Counting/Reuse.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Counting.h"
#include "idr/Transforms/Counting/Bound.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

namespace idr {
#define GEN_PASS_DEF_IDRRCREUSE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::counting::reuse {

//===----------------------------------------------------------------------===//
// The sizes
//===----------------------------------------------------------------------===//

unsigned Reuse::cellBytes(Type value) const {
  return layouts.cells(cast<DataType>(unrestricted(value))).cell(*knownConstructor(value)).size;
}

std::optional<unsigned> Reuse::indexOf(unsigned bytes) const {
  auto at = llvm::find(sizes, bytes);
  if (at == sizes.end())
    return std::nullopt;
  return static_cast<unsigned>(at - sizes.begin());
}

// A take whose token is freed right after it, or a drop of a value whose
// type fixes a constructor with a cell: a cell of that size may become free
// here.
std::optional<unsigned> Reuse::sourceBytes(Operation *op) const {
  if (auto take = dyn_cast<CountTakeOp>(op)) {
    Value token = take.getToken();
    if (token.hasOneUse() && isa<TokenFreeOp>(*token.user_begin()))
      return cellBytes(take.getValue().getType());
    return std::nullopt;
  }
  if (auto drop = dyn_cast<CountDropOp>(op)) {
    Type type = drop.getValue().getType();
    std::optional<Tag> tag = knownConstructor(type);
    if (tag && !isMemo(type) && buildsCell(type, *tag))
      return cellBytes(type);
  }
  return std::nullopt;
}

//===----------------------------------------------------------------------===//
// The rebuilds, the fusions and the pass
//===----------------------------------------------------------------------===//

// Each rebuild the in-place rule decided: its token's cell recycled for the
// constructor its type names, and the fields written into it.
void Reuse::lowerRebuilds() {
  llvm::SmallVector<TokenRebuildOp> found;
  fn.walk([&](TokenRebuildOp rebuild) { found.push_back(rebuild); });
  IRRewriter rewriter(fn->getContext());
  for (TokenRebuildOp rebuild : found) {
    rewriter.setInsertionPoint(rebuild);
    Type value = rebuild.getResult().getType();
    auto cellType = CellType::get(rewriter.getContext(), cast<DataType>(unrestricted(value)));
    auto cell = CellRecycleOp::create(rewriter, rebuild.getLoc(), cellType, rebuild.getToken());
    auto init = CellInitOp::create(rewriter, rebuild.getLoc(), value, cell.getCell(),
                                   rebuild.getFields(), ArrayRef<int32_t>());
    rewriter.replaceOp(rebuild, init.getResult());
    ++rebuilds;
  }
}

// A take whose token one recycle in its own block consumes fuses with it:
// the take gives the cell, with no token between.
void Reuse::fuse() {
  llvm::SmallVector<CountTakeOp> takes;
  fn.walk([&](CountTakeOp take) { takes.push_back(take); });
  IRRewriter rewriter(fn->getContext());
  for (CountTakeOp take : takes) {
    Value token = take.getToken();
    if (!token.hasOneUse())
      continue;
    auto recycle = dyn_cast<CellRecycleOp>(*token.user_begin());
    if (!recycle || recycle->getBlock() != take->getBlock())
      continue;
    rewriter.setInsertionPoint(take);
    auto into = CountTakeIntoOp::create(rewriter, take.getLoc(), recycle.getCell().getType(), take.getValue());
    rewriter.replaceAllUsesWith(take.getFields(), into.getFields());
    rewriter.replaceAllUsesWith(recycle.getCell(), into.getCell());
    rewriter.eraseOp(recycle);
    rewriter.eraseOp(take);
    ++fused;
  }
}

void Reuse::run() {
  lowerRebuilds();
  demands();
  if (!sizes.empty())
    assign();
  fuse();
}

namespace {

struct ReusePass : impl::IdrRcReuseBase<ReusePass> {
  void runOnProgram(ProgramOp) {
    FuncOp fn = getOperation();
    const Layouts &layouts = getAnalysis<Layouts>();
    Reuse reuse(fn, layouts);
    reuse.run();
    std::uint64_t bound = frameBound(fn, layouts);
    fn.setFrameBound(bound);
    numReuses += reuse.reuses;
    numTokensFreed += reuse.freed;
    numFused += reuse.fused;
    numRebuilds += reuse.rebuilds;
    frameBoundBytes.updateMax(bound);
  }
};

} // namespace

} // namespace idr::counting::reuse
