// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one linearity rule, after every pass. A value used once by its grade's
// uses is used at most once on every path, field by field: a field read
// takes that field alone, as a match binds each field of its scrutinee
// once; an op that ends the value's owner (a drop, a take, the fused take,
// the test of sharing, an unpack) takes the cell alone, which is counting
// giving the value up after its last use, no use Idris counted; and every
// other use takes the whole value, every field with it. A value used once
// by its type (a cell, a destination, a package) is used exactly once on
// every path that goes on: its one use is what takes it (an init fills the
// cell, a write fills the destination, an unpack reopens the package), so a
// path without it leaves memory nothing fills or gives back. Once the
// program is counted, a value that holds a reference of its own moves it
// on exactly once on every path that goes on, by the one rule counting
// places by (referenceAt): given up, handed on whole (a yield, a jump, a
// match's entering operand, a cast, a call, a constructor's field), its
// owner ended, or lent and given back. All three are
// one count: the uses that count, on the worst path, the most over a
// match's alternatives, the sum over regions that run one after another,
// twice for a region that runs again. A path that ends the run (a crash,
// an exit) gives nothing up, since nothing after it runs. A value with one
// use that counts, in the block that defines it, is settled with no walk;
// only past one is a region looked into.
//
// Which regions of an op exclude each other is asked of
// RegionBranchOpInterface once per op class in one verify.

#include "idr/IR/Counting/Counting.h"
#include "idr/IR/Counting/Traits.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Ownership.h"
#include "idr/IR/Regions.h"
#include "idr/IR/Verify.h"
#include "idr/Support/Match.h"

// Whether the program's references are counted (StageCounting).
#include "idr/IR/Generated/StageFacts.h.inc"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <concepts>
#include <cstdint>
#include <optional>
#include <utility>
#include <variant>

using namespace mlir;
using namespace idr;

namespace {

// What a value is held to: at most one use on every path (a value its grade
// uses once, of each field); exactly one use on every path that goes on (a
// value its type uses once); or exactly one use that moves its reference on
// on every path that goes on, the uses that keep it not counting (a counted
// value).
enum class Obligation : std::uint8_t { UsedAtMostOnce, UsedExactlyOnce, ConsumedExactlyOnce };

// Whether `obligation` holds a value to its uses, or to the giving up of its
// reference.
constexpr bool everyUse(Obligation obligation) {
  return obligation != Obligation::ConsumedExactlyOnce;
}

// Whether `obligation` asks for exactly one on every path that goes on, not at
// most one.
constexpr bool exactly(Obligation obligation) {
  return obligation != Obligation::UsedAtMostOnce;
}

// Which uses of a value one count counts.
template <typename Counts>
concept UseFilter = std::predicate<Counts &, OpOperand &>;

// Whether a path through a region goes on to what follows it, or ends the
// run first.
enum class Reach : std::uint8_t { GoesOn, EndsRun };

// One path's account of a value: where it goes, and the uses that count on
// it.
struct Account {
  Reach reach;
  unsigned uses;
};

// How an op's regions run: in turn, each counted beside the rest (a loop's,
// a join point's); or as alternatives, one of which runs (a match's).
enum class Regions : std::uint8_t { InTurn, OneOf };

// Asked once per op class: a fact of the class, which every op of it shares.
class Exclusivity {
public:
  Regions of(Operation *op) {
    auto branch = dyn_cast<RegionBranchOpInterface>(op);
    if (!branch)
      return Regions::InTurn;
    for (const auto &[name, answer] : asked)
      if (name == op->getName())
        return answer;
    // Alternatives each return straight to the op, never to another region.
    Regions answer = Regions::OneOf;
    for (Region &region : branch->getRegions()) {
      SmallVector<RegionSuccessor> next;
      branch.getSuccessorRegions(region, next);
      if (!llvm::all_of(next, [](RegionSuccessor &successor) { return successor.isOperation(); }))
        answer = Regions::InTurn;
    }
    asked.emplace_back(op->getName(), answer);
    return answer;
  }

private:
  SmallVector<std::pair<OperationName, Regions>, 8> asked;
};

// Whether the last op of `block` ends the run: a terminator with no
// successor that returns to no op and breaks to no join point (a crash, an
// exit, an unreachable). A return returns to its function's caller, and
// upstream's ReturnLike makes it a region branch's terminator too. A jump
// to a join point goes on, to the join point's region, which its op counts
// after it.
bool endsRun(Block &block) {
  if (block.empty())
    return false;
  Operation &last = block.back();
  return last.hasTrait<OpTrait::IsTerminator>() && last.getNumSuccessors() == 0 &&
         !isa<RegionBranchTerminatorOpInterface>(last) &&
         !isa<HasBreakingControlFlowOpInterface>(last);
}

// The count of one value under one obligation, of the uses `counts` takes.
class Count {
public:
  template <UseFilter Counts>
  Count(Value value, Obligation obligation, Exclusivity &exclusivity, Counts &&counts)
      : value(value), obligation(obligation), exclusivity(exclusivity) {
    for (OpOperand &use : value.getUses())
      if (counts(use))
        users.push_back(use.getOwner());
  }

  LogicalResult check() {
    // No use that counts: none is a second, and at most one asks for none.
    if (users.empty() && !exactly(obligation))
      return success();
    Block &home = *(isa<BlockArgument>(value) ? cast<BlockArgument>(value).getOwner()
                                              : value.getDefiningOp()->getBlock());
    // One use that counts, in the block that defines the value and in no
    // region below it: every path that goes on passes it, once.
    if (users.size() == 1 && users.front()->getBlock() == &home)
      return success();
    FailureOr<Account> account = accountOf(home);
    if (failed(account))
      return failure();
    if (!exactly(obligation) || account->reach == Reach::EndsRun || account->uses == 1)
      return success();
    return emitError(value.getLoc())
           << (obligation == Obligation::UsedExactlyOnce
                   ? "is used once by its type and never used on a path that goes on"
                   : "holds a reference that is never given up on a path that goes on");
  }

private:
  // The uses that count which `op` makes itself.
  unsigned own(Operation *op) const { return static_cast<unsigned>(llvm::count(users, op)); }

  // Whether a use that counts lies inside `op`'s regions, or inside `region`.
  bool holds(Operation *op) const {
    return llvm::any_of(users, [&](Operation *user) { return user != op && op->isAncestor(user); });
  }
  bool holds(Region &region) const {
    return llvm::any_of(users,
                        [&](Operation *user) { return region.isAncestor(user->getParentRegion()); });
  }

  LogicalResult tooMany(Operation &op) {
    return op.emitOpError(everyUse(obligation)
                              ? "uses a value used once that is already used on the same path"
                              : "gives up a reference already given up on the same path");
  }

  // The account of `home`'s ops, each op whose regions hold a use looked
  // into: the blocks and the region ops still being counted wait on a list,
  // never on the C++ stack, so a deep nest of regions costs memory, not
  // native frames. Each step that ends hands its account to the one below
  // it, and the last to end, home's block, hands it back.
  FailureOr<Account> accountOf(Block &home) {
    // A block whose ops are being counted, and the op whose regions it
    // waits on.
    struct InBlock {
      Block *block;
      Block::iterator next;
      unsigned uses;
      Operation *waiting;
    };
    // An op whose regions are being counted: how they run, the region with
    // a use being looked into and its block now, and each region's account,
    // the last that region's so far. Past the last region, only `each` is.
    struct InRegions {
      Operation *op;
      Regions regions;
      unsigned region;
      Region::iterator block;
      SmallVector<Account, 4> each;
    };
    SmallVector<std::variant<InBlock, InRegions>, 8> steps;
    steps.push_back(InBlock{&home, home.begin(), 0, nullptr});
    std::optional<Account> returned;
    // The step on top ends with `done`. A case that ends its step, or puts
    // another above it, reads its step no more: the list moves under it.
    auto finish = [&](Account done) -> LogicalResult {
      steps.pop_back();
      returned = done;
      return success();
    };
    // Moves `at` into the first region from its own that a use lies in;
    // one before it has no use, and ends the run if its one block does.
    auto enter = [&](InRegions &at) {
      for (; at.region < at.op->getNumRegions(); ++at.region) {
        Region &region = at.op->getRegion(at.region);
        if (!region.empty() && holds(region)) {
          at.block = region.begin();
          at.each.push_back(Account{Reach::GoesOn, 0});
          return;
        }
        bool ends = region.hasOneBlock() && endsRun(region.front());
        at.each.push_back(Account{ends ? Reach::EndsRun : Reach::GoesOn, 0});
      }
    };
    while (!steps.empty())
      if (failed(match(
              steps.back(),
              [&](InBlock &in) -> LogicalResult {
                if (returned) {
                  Operation &op = *in.waiting;
                  Account inner = *std::exchange(returned, std::nullopt);
                  in.uses += inner.uses;
                  if (in.uses > 1)
                    return tooMany(op);
                  if (inner.reach == Reach::EndsRun)
                    return finish(Account{Reach::EndsRun, in.uses});
                }
                if (in.next == in.block->end())
                  return finish(
                      Account{endsRun(*in.block) ? Reach::EndsRun : Reach::GoesOn, in.uses});
                Operation &op = *in.next++;
                in.uses += own(&op);
                if (op.getNumRegions() != 0 && holds(&op)) {
                  in.waiting = &op;
                  InRegions at{&op, exclusivity.of(&op), 0, {}, {}};
                  enter(at);
                  steps.push_back(std::move(at));
                  return success();
                }
                if (in.uses > 1)
                  return tooMany(op);
                return success();
              },
              [&](InRegions &at) -> LogicalResult {
                if (returned) {
                  Account inner = *std::exchange(returned, std::nullopt);
                  at.each.back().uses += inner.uses;
                  if (at.op->getRegion(at.region).hasOneBlock())
                    at.each.back().reach = inner.reach;
                  ++at.block;
                }
                if (at.region < at.op->getNumRegions()) {
                  if (at.block != at.op->getRegion(at.region).end()) {
                    Block &block = *at.block;
                    steps.push_back(InBlock{&block, block.begin(), 0, nullptr});
                    return success();
                  }
                  // The region is counted: twice if it runs again, beside
                  // regions that run one after another.
                  unsigned &uses = at.each.back().uses;
                  if (at.regions == Regions::InTurn && uses != 0 &&
                      regionRuns(at.op, at.region) == Runs::Repeatedly)
                    uses *= 2;
                  ++at.region;
                  enter(at);
                  return success();
                }
                FailureOr<Account> done = combined(*at.op, at.regions, at.each);
                if (failed(done))
                  return failure();
                return finish(*done);
              })))
        return failure();
    return *returned;
  }

  // The account of an op from its regions' accounts, `each`: the sum over
  // regions that run one after another; over alternatives, one runs.
  FailureOr<Account> combined(Operation &op, Regions regions, ArrayRef<Account> each) {
    if (regions == Regions::InTurn) {
      unsigned uses = 0;
      for (const Account &account : each)
        uses += account.uses;
      bool ends = !each.empty() && llvm::all_of(each, [](const Account &account) {
        return account.reach == Reach::EndsRun;
      });
      return Account{ends ? Reach::EndsRun : Reach::GoesOn, uses};
    }
    // A value used at most once is used at most as often as the most any
    // alternative uses it; a value used or given up exactly once is used as
    // often on every alternative that goes on.
    std::optional<unsigned> goesOn;
    unsigned most = 0;
    for (const Account &account : each) {
      most = std::max(most, account.uses);
      if (account.reach == Reach::EndsRun)
        continue;
      if (exactly(obligation) && goesOn && *goesOn != account.uses)
        return op.emitOpError(obligation == Obligation::UsedExactlyOnce
                                  ? "uses a value used once by its type on one alternative and not "
                                    "on another"
                                  : "gives up a reference on one alternative and not on another");
      goesOn = account.uses;
    }
    if (!exactly(obligation))
      return Account{goesOn ? Reach::GoesOn : Reach::EndsRun, most};
    return Account{goesOn ? Reach::GoesOn : Reach::EndsRun, goesOn.value_or(0)};
  }

  Value value;
  Obligation obligation;
  Exclusivity &exclusivity;
  SmallVector<Operation *, 4> users;
};

// Every use counts.
bool anyUse(OpOperand &) { return true; }

// What one use takes of the value it uses. A field read takes the field it
// reads and no other, and so does the opening of the buffer a field holds,
// whose array is that field. A use that ends the value's owner, as its first
// operand (EndsOwner: a drop, a take, the fused take, the test of sharing,
// an unpack), takes the cell alone: it gives up the reference, and every
// field with it, or moves each field out as a value of its own, which
// carries on the uses a read of that field had. Every other use takes the
// whole value, every field with it.
struct TakesField {
  std::uint64_t index;
};
struct TakesCell {};
struct TakesWhole {};
using Taken = std::variant<TakesField, TakesCell, TakesWhole>;

Taken takenBy(OpOperand &use) {
  Operation *user = use.getOwner();
  if (auto read = dyn_cast<DataFieldOp>(user))
    return TakesField{read.getIndex()};
  if (auto open = dyn_cast<ArrayOpenOp>(user))
    return TakesField{open.getIndex()};
  if (user->hasTrait<EndsOwner>() && use.getOperandNumber() == 0)
    return TakesCell{};
  return TakesWhole{};
}

// Whether `use` takes field `index` of the value it uses.
bool takesField(OpOperand &use, std::uint64_t index) {
  return match(
      takenBy(use), [&](TakesField field) { return field.index == index; },
      [](TakesCell) { return false; }, [](TakesWhole) { return true; });
}

// Whether `use` takes some field of the value it uses.
bool takesAField(OpOperand &use) {
  return match(
      takenBy(use), [](OneOf<TakesField, TakesWhole> auto) { return true; },
      [](TakesCell) { return false; });
}

// A value its grade uses once is used at most once on every path, field by
// field: each field some use reads is counted with the uses that take the
// whole value, so a field read twice, or read beside a use of the whole, is
// a second use of it. A value no use reads a field of is counted whole. A
// use that takes the cell alone is in no count: it ends the owner after the
// value's last use, where counting or the in-place check puts it, and once
// the program is counted the count of the uses that move the reference on
// holds it, beside every other such use, to exactly one.
LogicalResult usedAtMostOnceEachField(Value value, Exclusivity &exclusivity) {
  SmallVector<std::uint64_t, 4> read;
  for (OpOperand &use : value.getUses())
    match(
        takenBy(use),
        [&](TakesField field) {
          if (!llvm::is_contained(read, field.index))
            read.push_back(field.index);
        },
        [](OneOf<TakesCell, TakesWhole> auto) {});
  if (read.empty())
    return Count(value, Obligation::UsedAtMostOnce, exclusivity, takesAField).check();
  for (std::uint64_t index : read)
    if (failed(Count(value, Obligation::UsedAtMostOnce, exclusivity,
                     [index](OpOperand &use) { return takesField(use, index); })
                   .check()))
      return failure();
  return success();
}

} // namespace

LogicalResult idr::verify::linearity(FuncOp fn) {
  StageCounting counting = countingAt[fn.getProgram().getStage()];
  Exclusivity exclusivity;
  auto checkValue = [&](Value value) -> LogicalResult {
    Type type = value.getType();
    if (counting == StageCounting::Counted && isa<idr::ReuseTokenType>(unrestricted(type)) &&
        usesOf(type) == Uses::Many)
      return emitError(value.getLoc()) << "holds a reuse token at many uses";
    // A constant holds nothing a use could take: a folder materializes one
    // wherever it is needed, merges equal ones and hoists them out of
    // loops, so its uses repeat however the program was written.
    if (matchPattern(value, m_Constant()))
      return success();
    // Used once by its type: the type alone says so at every stage, and no
    // grade is written on it.
    if (isLinearByType(type))
      return Count(value, Obligation::UsedExactlyOnce, exclusivity, anyUse).check();
    if (usesOf(type) == Uses::Once && failed(usedAtMostOnceEachField(value, exclusivity)))
      return failure();
    if (counting != StageCounting::Counted || !freedBy(type, Release::Counted))
      return success();
    // A loan to upstream's ops, and a view of one, is a reference of no
    // one's: nothing gives it up, as the rule of loans holds.
    if (lifetimes::loanOf(value))
      return success();
    // A part read with no reference of its own is given up with its owner,
    // whose one move counts for it: a use moving it on is a second.
    if (ownership::ownerOfPart(value)) {
      for (OpOperand &use : value.getUses())
        if (referenceAt(use) == Reference::MovedOn)
          return use.getOwner()->emitOpError("moves on a part that its owner gives up");
      return success();
    }
    return Count(value, Obligation::ConsumedExactlyOnce, exclusivity,
                 [](OpOperand &use) { return referenceAt(use) == Reference::MovedOn; })
        .check();
  };
  WalkResult walked = fn->walk<WalkOrder::PreOrder>([&](Operation *op) {
    for (Value result : op->getResults())
      if (failed(checkValue(result)))
        return WalkResult::interrupt();
    for (Region &region : op->getRegions())
      for (Block &block : region)
        for (BlockArgument arg : block.getArguments())
          if (failed(checkValue(arg)))
            return WalkResult::interrupt();
    return WalkResult::advance();
  });
  return failure(walked.wasInterrupted());
}
