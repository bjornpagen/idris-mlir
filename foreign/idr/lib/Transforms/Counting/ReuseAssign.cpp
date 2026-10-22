// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-reuse's assignment (Reuse.h): one forward walk per function over
// its regions. A source whose token some path ahead can use keeps it, and
// a sink recycles the best token of its size by one total order, never a
// token no path ahead needs. Across a match's rejoin a token leaves as a
// result of the match, as many of each size as every region that rejoins
// holds and the code after it can use; the rest are freed where they end.
// A token is freed before a return, a call in tail position and a jump,
// and passes a call that is not in tail position, held by its frame.
#include "idr/Transforms/Counting/Reuse.h"

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Builders.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <tuple>
#include <variant>

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
    Type type = held.token.value().getType();
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

} // namespace idr::counting::reuse
