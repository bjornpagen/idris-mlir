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
#include "Counting.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Layout.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Quantities.h"
#include "idr/Transforms/Counting.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <optional>
#include <tuple>
#include <variant>

namespace idr {
#define GEN_PASS_DEF_IDRRCREUSE
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::counting {
namespace {

// The most sinks of each size of the function's sources on some path ahead,
// one count per size, capped by how many sources of that size there are: a
// count that only grows over a finite set.
using Demand = llvm::SmallVector<std::uint32_t, 4>;

void raise(Demand &into, const Demand &other) {
  for (auto [a, b] : llvm::zip_equal(into, other))
    a = std::max(a, b);
}

// A token held on the forward walk's path: the size it may be recycled
// into, its place in the order of choice, and the handle that consumes it
// once.
struct Held {
  unsigned size;
  std::uint32_t order;
  Token token;
};

class Reuse {
public:
  Reuse(FuncOp fn, const Layouts &layouts) : fn(fn), layouts(layouts) {}

  void run();

  unsigned reuses = 0;
  unsigned freed = 0;
  unsigned fused = 0;
  unsigned rebuilds = 0;
  // The most bytes the walk held in tokens at one point: what a frame holds
  // of dead cells, for the frame bound's record.
  unsigned largestHeld = 0;

private:
  unsigned cellBytes(Type value) const;
  std::optional<unsigned> sourceBytes(Operation *op) const;
  std::optional<unsigned> indexOf(unsigned bytes) const;
  Demand none() const { return Demand(sizes.size(), 0); }

  void demands();
  void assign();
  void freeAll(llvm::SmallVector<Held> &held, Operation *before);
  Operation *withTokenResults(Operation *op, llvm::ArrayRef<Type> tokens);
  void lowerRebuilds();
  void fuse();

  FuncOp fn;
  const Layouts &layouts;
  // The sizes the function's sources give, numbered densely.
  llvm::SmallVector<unsigned, 4> sizes;
  // What the backward walk measured, in the order it met each point: after
  // each region op, after each source, at each region's head.
  std::vector<Demand> trail;
  std::uint32_t nextOrder = 0;
};

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
// The demand
//===----------------------------------------------------------------------===//

void Reuse::demands() {
  Demand cap;
  fn.walk([&](Operation *op) {
    std::optional<unsigned> bytes = sourceBytes(op);
    if (!bytes)
      return;
    if (!indexOf(*bytes)) {
      sizes.push_back(*bytes);
      cap.push_back(0);
    }
    ++cap[*indexOf(*bytes)];
  });
  if (sizes.empty())
    return;
  struct BlockAt {
    Block *block;
    Operation *next;
    Demand demand;
    unsigned region;
  };
  struct OpAt {
    Operation *op;
    Runs runs;
    Demand after;
    unsigned remaining;
    llvm::SmallVector<Demand, 2> entries;
  };
  llvm::SmallVector<std::variant<BlockAt, OpAt>, 16> stack;
  Block &body = fn.getBody().front();
  stack.push_back(BlockAt{&body, &body.back(), none(), 0});
  while (!stack.empty()) {
    if (auto *at = std::get_if<OpAt>(&stack.back())) {
      if (at->remaining > 0) {
        Region &region = at->op->getRegion(--at->remaining);
        if (!region.empty())
          stack.push_back(BlockAt{&region.front(), &region.front().back(), none(), region.getRegionNumber()});
        continue;
      }
      // Before an op that enters one region once: the most any region it
      // enters asks. Before one that repeats: what is asked after it, since
      // no token from outside enters it.
      Demand before = at->after;
      if (at->runs == Runs::Once) {
        before = none();
        llvm::SmallVector<RegionSuccessor> entries;
        cast<RegionBranchOpInterface>(at->op).getSuccessorRegions(RegionBranchPoint::parent(), entries);
        for (const RegionSuccessor &entry : entries)
          raise(before, at->entries[entry.getSuccessor()->getRegionNumber()]);
      }
      stack.pop_back();
      std::get<BlockAt>(stack.back()).demand = std::move(before);
      continue;
    }
    auto &walk = std::get<BlockAt>(stack.back());
    if (!walk.next) {
      BlockAt done = std::move(walk);
      stack.pop_back();
      trail.push_back(done.demand);
      if (!stack.empty())
        std::get<OpAt>(stack.back()).entries[done.region] = std::move(done.demand);
      continue;
    }
    Operation *op = walk.next;
    walk.next = op->getPrevNode();
    if (op->hasTrait<OpTrait::IsTerminator>()) {
      // A yield to an op around that enters one region once asks what is
      // asked after that op; every other way out lets the tokens die.
      walk.demand = none();
      if (auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(op)) {
        llvm::SmallVector<Attribute> constants(op->getNumOperands());
        llvm::SmallVector<RegionSuccessor> successors;
        terminator.getSuccessorRegions(constants, successors);
        for (const RegionSuccessor &successor : successors) {
          if (!successor.isOperation() || successor.getSuccessorOp() != op->getParentOp())
            continue;
          for (auto &frame : llvm::reverse(stack))
            if (auto *around = std::get_if<OpAt>(&frame); around && around->op == op->getParentOp()) {
              if (around->runs == Runs::Once)
                raise(walk.demand, around->after);
              break;
            }
        }
      }
      continue;
    }
    if (auto sink = dyn_cast<CellNewOp>(op))
      if (std::optional<unsigned> index = indexOf(cellBytes(sink.getCell().getType().getValue())))
        walk.demand[*index] = std::min(walk.demand[*index] + 1, cap[*index]);
    if (sourceBytes(op))
      trail.push_back(walk.demand);
    if (auto call = dyn_cast<CallOp>(op); call && call.getTailKind() == TailKind::tail)
      walk.demand = none();
    if (op->getNumRegions() != 0) {
      trail.push_back(walk.demand);
      OpAt at{op, runsOf(op), walk.demand, op->getNumRegions(), {}};
      at.entries.assign(op->getNumRegions(), none());
      stack.push_back(std::move(at));
    }
  }
}

//===----------------------------------------------------------------------===//
// The assignment
//===----------------------------------------------------------------------===//

void Reuse::freeAll(llvm::SmallVector<Held> &held, Operation *before) {
  OpBuilder b(before);
  for (Held &each : held) {
    TokenFreeOp::create(b, before->getLoc(), std::move(each.token).consume());
    ++freed;
  }
  held.clear();
}

// The order of choice among tokens of one size for a sink: a token the type
// proves unique (never null, no test), then one of the sink's own
// constructor (its header kept), then the earliest.
auto rankFor(Type sinkValue) {
  return [sinkValue](const Held &held) {
    Type type = held.token.value().getType();
    bool unique = claims(type, Unique::Deep);
    bool own = llvm::is_contained(cast<TokenType>(unrestricted(type)).getSources(),
                                  cast<DataType>(unrestricted(sinkValue)));
    return std::tuple(!unique, !own, held.order);
  };
}

// `op`, made again with `tokens` as results after its own: the tokens a
// match's regions all hold leave it as results, which each region's yield
// passes.
Operation *Reuse::withTokenResults(Operation *op, llvm::ArrayRef<Type> tokens) {
  llvm::SmallVector<Type> types(op->getResultTypes());
  llvm::append_range(types, tokens);
  OpBuilder b(op);
  Operation *rebuilt = Operation::create(op->getLoc(), op->getName(), types, op->getOperands(),
                                         op->getAttrDictionary(), op->getPropertiesStorage(),
                                         op->getSuccessors(), op->getNumRegions());
  b.insert(rebuilt);
  for (auto [from, to] : llvm::zip_equal(op->getRegions(), rebuilt->getRegions()))
    to.takeBody(from);
  op->replaceAllUsesWith(rebuilt->getResults().take_front(op->getNumResults()));
  op->erase();
  return rebuilt;
}

void Reuse::assign() {
  struct Path {
    Block *block;
    Operation *next;
    llvm::SmallVector<Held> held;
    unsigned region;
  };
  struct Regions {
    Operation *op;
    Runs runs;
    // The tokens the path held before the op: handed to each region it
    // enters, as the paths of which exactly one runs; held past an op that
    // repeats, which no token from outside enters.
    llvm::SmallVector<Held> outside;
    unsigned nextRegion;
    llvm::SmallVector<bool, 2> entered;
    // What each region that rejoins holds at its yield.
    llvm::SmallVector<std::optional<llvm::SmallVector<Held>>, 2> leftover;
  };
  llvm::SmallVector<std::variant<Path, Regions>, 16> stack;
  auto count = [](const llvm::SmallVector<Held> &held, unsigned size) {
    return static_cast<std::uint32_t>(llvm::count_if(held, [&](const Held &h) { return h.size == size; }));
  };
  auto wants = [](const Demand &demand, unsigned index) { return demand[index]; };
  Block &body = fn.getBody().front();
  trail.pop_back();
  stack.push_back(Path{&body, &body.front(), {}, 0});
  while (!stack.empty()) {
    if (auto *regions = std::get_if<Regions>(&stack.back())) {
      Operation *op = regions->op;
      if (regions->nextRegion < op->getNumRegions()) {
        Region &region = op->getRegion(regions->nextRegion++);
        if (region.empty())
          continue;
        Block &entry = region.front();
        Demand head = std::move(trail.back());
        trail.pop_back();
        llvm::SmallVector<Held> start;
        if (regions->runs == Runs::Once && regions->entered[region.getRegionNumber()]) {
          // A token the region cannot use is freed at its head.
          OpBuilder b(&entry, entry.begin());
          for (Held &each : regions->outside) {
            unsigned index = *indexOf(each.size);
            if (count(start, each.size) < wants(head, index)) {
              start.push_back(Held{each.size, each.order, Token(each.token.value())});
              continue;
            }
            TokenFreeOp::create(b, op->getLoc(), each.token.value());
            ++freed;
          }
        }
        stack.push_back(Path{&entry, &entry.front(), std::move(start), region.getRegionNumber()});
        continue;
      }
      Regions done = std::move(*regions);
      stack.pop_back();
      Demand ahead = std::move(trail.back());
      trail.pop_back();
      llvm::SmallVector<Held> after;
      if (done.runs == Runs::Repeats) {
        after = std::move(done.outside);
      } else {
        // Each region holds its own handle on what was handed to it.
        for (Held &each : done.outside)
          (void)std::move(each.token).consume();
        bool rebuildable = isa<RegionBranchOpInterface>(done.op) &&
                           !done.op->hasTrait<OpTrait::AttrSizedResultSegments>();
        // As many of each size as every region that rejoins holds and the
        // code after the op can use.
        llvm::SmallVector<unsigned> carried;
        for (auto [index, size] : llvm::enumerate(sizes)) {
          std::optional<std::uint32_t> least;
          for (auto &left : done.leftover)
            if (left)
              least = std::min(least.value_or(~0u), count(*left, size));
          std::uint32_t k = rebuildable && least ? std::min(*least, wants(ahead, index)) : 0;
          carried.append(k, size);
        }
        llvm::SmallVector<Type> types;
        llvm::SmallVector<llvm::SmallVector<Value>> yielded(done.leftover.size());
        for (unsigned size : carried) {
          llvm::SmallVector<TokenType> sources;
          bool unique = true;
          for (auto [r, left] : llvm::enumerate(done.leftover)) {
            if (!left)
              continue;
            auto pick = llvm::min_element(*left, [&](const Held &a, const Held &b) {
              if ((a.size == size) != (b.size == size))
                return a.size == size;
              return a.order < b.order;
            });
            Value token = std::move(pick->token).consume();
            left->erase(pick);
            yielded[r].push_back(token);
            sources.push_back(cast<TokenType>(unrestricted(token.getType())));
            unique = unique && claims(token.getType(), Unique::Deep);
          }
          types.push_back(graded(Grade{Uses::Once, Hold::counted(unique ? Unique::Deep : Unique::None)},
                                 TokenType::merged(sources)));
        }
        for (Region &region : done.op->getRegions()) {
          auto &left = done.leftover[region.getRegionNumber()];
          if (region.empty() || !left)
            continue;
          Operation *terminator = region.front().getTerminator();
          OpBuilder b(terminator);
          for (Held &rest : *left) {
            TokenFreeOp::create(b, terminator->getLoc(), std::move(rest.token).consume());
            ++freed;
          }
          if (carried.empty())
            continue;
          // Each path gives its token at the rejoin's type: a share forgets
          // which of the sources it is and, where another path's is not,
          // that it is unique.
          llvm::SmallVector<Value> given;
          for (auto [slot, token] : llvm::enumerate(yielded[region.getRegionNumber()]))
            given.push_back(token.getType() == types[slot]
                                ? token
                                : CountShareOp::create(b, terminator->getLoc(), types[slot], token)
                                      .getResult());
          cast<RegionBranchTerminatorOpInterface>(terminator)
              .getMutableSuccessorOperands(RegionSuccessor(done.op))
              .append(given);
        }
        if (!carried.empty()) {
          Operation *rebuilt = withTokenResults(done.op, types);
          unsigned first = rebuilt->getNumResults() - static_cast<unsigned>(carried.size());
          for (auto [slot, size] : llvm::enumerate(carried))
            after.push_back(Held{size, nextOrder++,
                                 Token(cast<TypedValue<TokenType>>(rebuilt->getResult(first + slot)))});
          done.op = rebuilt;
        }
      }
      auto &path = std::get<Path>(stack.back());
      for (Held &each : after)
        path.held.push_back(std::move(each));
      path.next = done.op->getNextNode();
      continue;
    }
    auto &path = std::get<Path>(stack.back());
    if (!path.next) {
      stack.pop_back();
      continue;
    }
    Operation *op = path.next;
    path.next = op->getNextNode();
    unsigned bytes = 0;
    for (const Held &h : path.held)
      bytes += h.size;
    largestHeld = std::max(largestHeld, bytes);
    if (op->hasTrait<OpTrait::IsTerminator>()) {
      switch (leavesOf(op)) {
      case Leaves::Frame:
        freeAll(path.held, op);
        break;
      case Leaves::Process:
        // Only the end follows: nothing is freed.
        for (Held &each : path.held)
          (void)std::move(each.token).consume();
        path.held.clear();
        break;
      case Leaves::Successors: {
        // A yield to the op around rejoins it; any other way on frees what
        // the path holds.
        Operation *parent = op->getParentOp();
        llvm::SmallVector<Attribute> constants(op->getNumOperands());
        llvm::SmallVector<RegionSuccessor> successors;
        cast<RegionBranchTerminatorOpInterface>(op).getSuccessorRegions(constants, successors);
        bool rejoins = llvm::all_of(successors, [&](const RegionSuccessor &s) {
          return s.isOperation() && s.getSuccessorOp() == parent;
        });
        auto *around = stack.size() >= 2 ? std::get_if<Regions>(&stack[stack.size() - 2]) : nullptr;
        if (rejoins && around && around->op == parent && around->runs == Runs::Once) {
          around->leftover[op->getParentRegion()->getRegionNumber()] = std::move(path.held);
          path.held.clear();
        } else {
          freeAll(path.held, op);
        }
        break;
      }
      }
      continue;
    }
    // A call modulo a context keeps its tokens: its context, which follows
    // it, may recycle one, and idr-trmc moves what follows the call before
    // it, where no token is read by the call.
    if (auto call = dyn_cast<CallOp>(op); call && call.getTailKind() == TailKind::tail) {
      freeAll(path.held, op);
      continue;
    }
    // A source keeps its token where a path ahead can use it.
    if (std::optional<unsigned> size = sourceBytes(op)) {
      Demand ahead = std::move(trail.back());
      trail.pop_back();
      if (count(path.held, *size) >= wants(ahead, *indexOf(*size)))
        continue;
      TypedValue<TokenType> token;
      if (auto take = dyn_cast<CountTakeOp>(op)) {
        (*take.getToken().user_begin())->erase();
        token = cast<TypedValue<TokenType>>(take.getToken());
      } else {
        // A drop of a value of a known constructor becomes its take, each
        // field dropped there, the emptied cell kept.
        auto drop = cast<CountDropOp>(op);
        OpBuilder b(drop);
        auto take = CountTakeOp::create(b, drop.getLoc(), drop.getValue());
        for (Value field : take.getFields())
          if (countsOf(field.getType()) == Counts::Counted)
            CountDropOp::create(b, drop.getLoc(), field);
        drop->erase();
        token = cast<TypedValue<TokenType>>(take.getToken());
      }
      path.held.push_back(Held{*size, nextOrder++, Token(token)});
      continue;
    }
    // A sink recycles the best token of its size.
    if (auto sink = dyn_cast<CellNewOp>(op)) {
      Type value = sink.getCell().getType().getValue();
      unsigned size = cellBytes(value);
      auto rank = rankFor(value);
      Held *best = nullptr;
      for (Held &h : path.held)
        if (h.size == size && (!best || rank(h) < rank(*best)))
          best = &h;
      if (!best)
        continue;
      OpBuilder b(sink);
      auto recycled = CellRecycleOp::create(b, sink.getLoc(), sink.getCell().getType(),
                                            std::move(best->token).consume());
      sink.getCell().replaceAllUsesWith(recycled.getCell());
      path.held.erase(best);
      sink->erase();
      ++reuses;
      continue;
    }
    if (op->getNumRegions() != 0) {
      Regions regions{op, runsOf(op), std::move(path.held), 0, {}, {}};
      path.held.clear();
      regions.entered.assign(op->getNumRegions(), false);
      regions.leftover.resize(op->getNumRegions());
      if (regions.runs == Runs::Once) {
        llvm::SmallVector<RegionSuccessor> entries;
        cast<RegionBranchOpInterface>(op).getSuccessorRegions(RegionBranchPoint::parent(), entries);
        for (const RegionSuccessor &entry : entries)
          regions.entered[entry.getSuccessor()->getRegionNumber()] = true;
      }
      stack.push_back(std::move(regions));
    }
  }
}

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

struct ReusePass : impl::IdrRcReuseBase<ReusePass> {
  void runOnProgram(ProgramOp) {
    Reuse reuse(getOperation(), getAnalysis<Layouts>());
    reuse.run();
    numReuses += reuse.reuses;
    numTokensFreed += reuse.freed;
    numFused += reuse.fused;
    numRebuilds += reuse.rebuilds;
    largestTokenBytes.updateMax(reuse.largestHeld);
  }
};

} // namespace
} // namespace idr::counting
