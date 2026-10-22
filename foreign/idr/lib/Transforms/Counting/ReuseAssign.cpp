// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-reuse's assignment (Reuse.h): one forward walk per function over
// its regions. A source whose token some path ahead can use keeps it, and
// a sink recycles the best token of its size by one total order, never a
// token no path ahead needs. A token held before an op that enters one of
// its regions once is handed to each region it enters, one handle per
// path, of which exactly one runs; a region that cannot use it frees its
// handle at its head. Across the op's rejoin a token leaves as a result of
// the op, as many of each size as every region that rejoins holds and the
// code after it can use; the rest are freed where they end. A token is
// freed before a return, a call in tail position and a jump, and passes a
// call that is not in tail position, held by its frame.
#include "idr/Transforms/Counting/Reuse.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <tuple>

using namespace mlir;

namespace idr::counting::reuse {

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

namespace {

// The order of choice among tokens of one size for a sink: a token the type
// proves unique (never null, no test), then one of the sink's own
// constructor (its header kept), then the earliest.
auto rankFor(Type sinkValue) {
  return [sinkValue](const Held &held) {
    Type type = held.token.type();
    bool unique = claims(type, Unique::Deep);
    bool own = llvm::is_contained(cast<TokenType>(unrestricted(type)).getSources(),
                                  cast<DataType>(unrestricted(sinkValue)));
    return std::tuple(!unique, !own, held.order);
  };
}

} // namespace

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

// The tokens the regions of `op` that rejoin it hold at their yields, of
// each size as many as every one of them holds and the code after the op
// can use (`ahead`), each region's yield passing its own at the rejoin's
// type; every other token a region holds is freed before its yield. Each
// region gives its earliest first. `op` is made again with the tokens that
// leave as its results, which the code after it holds.
llvm::SmallVector<Held> Reuse::carryAcross(Operation *&op,
                                           llvm::MutableArrayRef<std::optional<llvm::SmallVector<Held>>> leftover,
                                           const Demand &ahead) {
  llvm::SmallVector<Available<unsigned>> arms;
  llvm::SmallVector<Operation *> yields;
  for (Region &region : op->getRegions()) {
    std::optional<llvm::SmallVector<Held>> &left = leftover[region.getRegionNumber()];
    if (region.empty() || !left)
      continue;
    llvm::sort(*left, [](const Held &a, const Held &b) { return a.order < b.order; });
    Available<unsigned> arm;
    for (Held &each : *left)
      arm.tokens.emplace_back(each.size, std::move(each.token));
    arms.push_back(std::move(arm));
    yields.push_back(region.front().getTerminator());
  }
  bool rebuildable = isa<RegionBranchOpInterface>(op) && !op->hasTrait<OpTrait::AttrSizedResultSegments>();
  auto wanted = [&](const unsigned &size) -> std::uint32_t {
    return rebuildable ? ahead[*indexOf(size)] : 0;
  };
  // Each path gives its token at the rejoin's type: a share forgets which of
  // the sources it is and, where another path's is not, that it is unique.
  llvm::SmallVector<Type> types;
  auto join = [&](const unsigned &, llvm::SmallVector<Token> tokens) {
    llvm::SmallVector<TokenType> sources;
    bool unique = true;
    for (const Token &token : tokens) {
      sources.push_back(cast<TokenType>(unrestricted(token.type())));
      unique = unique && claims(token.type(), Unique::Deep);
    }
    Type type = graded(Grade{Uses::Once, Hold::counted(unique ? Unique::Deep : Unique::None)},
                       TokenType::merged(sources));
    types.push_back(type);
    for (auto [token, yield] : llvm::zip_equal(tokens, yields)) {
      OpBuilder b(yield);
      Value given = std::move(token).consume();
      if (given.getType() != type)
        given = CountShareOp::create(b, yield->getLoc(), type, given).getResult();
      cast<RegionBranchTerminatorOpInterface>(yield)
          .getMutableSuccessorOperands(RegionSuccessor(op))
          .append(given);
    }
  };
  auto drop = [&](unsigned at, const unsigned &, Token token) {
    OpBuilder b(yields[at]);
    TokenFreeOp::create(b, yields[at]->getLoc(), std::move(token).consume());
    ++freed;
  };
  llvm::SmallVector<unsigned> joined = rejoin(std::move(arms), wanted, join, drop);
  llvm::SmallVector<Held> after;
  if (joined.empty())
    return after;
  op = withTokenResults(op, types);
  unsigned first = op->getNumResults() - static_cast<unsigned>(joined.size());
  for (auto [slot, size] : llvm::enumerate(joined))
    after.push_back(Held{size, nextOrder++, Token(op->getResult(first + static_cast<unsigned>(slot)))});
  return after;
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
    // Per region, a handle on each token the path held before an op that
    // enters one region once, where the op enters it. An op that repeats
    // leaves its tokens on the path around it, since no token from outside
    // enters it.
    llvm::SmallVector<llvm::SmallVector<Held>, 2> handed;
    unsigned nextRegion;
    // What each region that rejoins holds at its yield.
    llvm::SmallVector<std::optional<llvm::SmallVector<Held>>, 2> leftover;
  };
  // The walk's frames alternate from the body down, a region op's on the
  // path it stands on and a region's path on its op's, so each kind has a
  // stack of its own: the top is a path exactly when there is one more path
  // than region ops, and the frame below either is the other stack's top.
  llvm::SmallVector<Path, 8> paths;
  llvm::SmallVector<Regions, 8> ops;
  auto count = [](const llvm::SmallVector<Held> &held, unsigned size) {
    return static_cast<std::uint32_t>(llvm::count_if(held, [&](const Held &h) { return h.size == size; }));
  };
  auto stepRegions = [&](Regions &regions) {
    Operation *op = regions.op;
    if (regions.nextRegion < op->getNumRegions()) {
      Region &region = op->getRegion(regions.nextRegion++);
      if (region.empty())
        return;
      Block &entry = region.front();
      Demand head = std::move(trail.back());
      trail.pop_back();
      // A token the region cannot use is freed at its head.
      llvm::SmallVector<Held> start;
      OpBuilder b(&entry, entry.begin());
      for (Held &each : regions.handed[region.getRegionNumber()]) {
        if (count(start, each.size) < head[*indexOf(each.size)]) {
          start.push_back(std::move(each));
          continue;
        }
        TokenFreeOp::create(b, op->getLoc(), std::move(each.token).consume());
        ++freed;
      }
      paths.push_back(Path{&entry, &entry.front(), std::move(start), region.getRegionNumber()});
      return;
    }
    Regions done = std::move(regions);
    ops.pop_back();
    Demand ahead = std::move(trail.back());
    trail.pop_back();
    llvm::SmallVector<Held> after;
    if (done.runs == Runs::Once)
      after = carryAcross(done.op, done.leftover, ahead);
    Path &path = paths.back();
    for (Held &each : after)
      path.held.push_back(std::move(each));
    path.next = done.op->getNextNode();
  };
  auto stepPath = [&](Path &path) {
    if (!path.next) {
      paths.pop_back();
      return;
    }
    Operation *op = path.next;
    path.next = op->getNextNode();
    if (op->hasTrait<OpTrait::IsTerminator>()) {
      switch (leavesOf(op)) {
      case Leaves::Frame:
        freeAll(path.held, op);
        return;
      case Leaves::Process:
        // Only the end follows: nothing is freed.
        for (Held &each : path.held)
          (void)std::move(each.token).consume();
        path.held.clear();
        return;
      case Leaves::Successors:
        break;
      }
      // A yield to the op around rejoins it; any other way on frees what
      // the path holds.
      Operation *parent = op->getParentOp();
      llvm::SmallVector<Attribute> constants(op->getNumOperands());
      llvm::SmallVector<RegionSuccessor> successors;
      cast<RegionBranchTerminatorOpInterface>(op).getSuccessorRegions(constants, successors);
      bool rejoins = llvm::all_of(successors, [&](const RegionSuccessor &s) {
        return s.isOperation() && s.getSuccessorOp() == parent;
      });
      // The op whose region the path walks, unless it is the body's.
      Regions *around = ops.empty() ? nullptr : &ops.back();
      if (rejoins && around && around->op == parent && around->runs == Runs::Once) {
        around->leftover[op->getParentRegion()->getRegionNumber()] = std::move(path.held);
        path.held.clear();
      } else {
        freeAll(path.held, op);
      }
      return;
    }
    // A call modulo a context keeps its tokens: its context, which follows
    // it, may recycle one, and idr-trmc moves what follows the call before
    // it, where no token is read by the call.
    if (auto call = dyn_cast<CallOp>(op); call && call.getTailKind() == TailKind::tail) {
      freeAll(path.held, op);
      return;
    }
    // A source keeps its token where a path ahead can use it.
    if (std::optional<unsigned> size = sourceBytes(op)) {
      Demand ahead = std::move(trail.back());
      trail.pop_back();
      if (count(path.held, *size) >= ahead[*indexOf(*size)])
        return;
      Value token;
      if (auto take = dyn_cast<CountTakeOp>(op)) {
        (*take.getToken().user_begin())->erase();
        token = take.getToken();
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
        token = take.getToken();
      }
      path.held.push_back(Held{*size, nextOrder++, Token(token)});
      return;
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
        return;
      OpBuilder b(sink);
      auto recycled = CellRecycleOp::create(b, sink.getLoc(), sink.getCell().getType(),
                                            std::move(best->token).consume());
      sink.getCell().replaceAllUsesWith(recycled.getCell());
      path.held.erase(best);
      sink->erase();
      ++reuses;
      return;
    }
    if (op->getNumRegions() == 0)
      return;
    Regions regions{op, runsOf(op), {}, 0, {}};
    regions.handed.resize(op->getNumRegions());
    regions.leftover.resize(op->getNumRegions());
    if (regions.runs == Runs::Once) {
      llvm::SmallVector<RegionSuccessor> entries;
      cast<RegionBranchOpInterface>(op).getSuccessorRegions(RegionBranchPoint::parent(), entries);
      for (Held &each : path.held) {
        llvm::SmallVector<Token> handles = branch(std::move(each.token), static_cast<unsigned>(entries.size()));
        for (auto [entry, handle] : llvm::zip_equal(entries, handles))
          regions.handed[entry.getSuccessor()->getRegionNumber()].push_back(
              Held{each.size, each.order, std::move(handle)});
      }
      path.held.clear();
    }
    ops.push_back(std::move(regions));
  };
  Block &body = fn.getBody().front();
  trail.pop_back();
  paths.push_back(Path{&body, &body.front(), {}, 0});
  while (!paths.empty()) {
    if (paths.size() > ops.size())
      stepPath(paths.back());
    else
      stepRegions(ops.back());
  }
}

} // namespace idr::counting::reuse
