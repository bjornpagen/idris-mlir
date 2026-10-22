// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one linearity rule, after every pass. A value used once by its grade's
// uses is used at most once on every path. A value used once by its type (a
// cell, a destination, a package) is used exactly once on every path that
// goes on: its one use is what takes it (an init fills the cell, a write
// fills the destination, an unpack reopens the package), so a path without
// it leaves memory nothing fills or gives back. Once the program is
// counted, a value that holds a reference of its own is given up exactly
// once on every path that goes on. All three are one count: the uses that
// count, on the worst path, the most over a match's alternatives, the sum
// over regions that run one after another, twice for a region that runs
// again. A path that ends the run (a crash, an exit) gives nothing up,
// since nothing after it runs. A value with one use that counts, in the
// block that defines it, is settled with no walk; only past one is a
// region looked into.
//
// Which regions of an op exclude each other is asked of
// RegionBranchOpInterface once per op class in one verify.

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Verify.h"

#include "mlir/IR/Matchers.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"

#include <algorithm>
#include <cstdint>

using namespace mlir;
using namespace idr;

// Each region returns straight to the op: the regions of a match or of an
// scf.if, not those of a loop or of a join point's regions, which run one
// after another.
bool idr::verify::alternatives(RegionBranchOpInterface branch) {
  return llvm::all_of(branch->getRegions(), [&](Region &region) {
    SmallVector<RegionSuccessor> next;
    branch.getSuccessorRegions(region, next);
    return llvm::all_of(next, [](RegionSuccessor &successor) { return successor.isOperation(); });
  });
}

namespace {

// What a value is held to: at most one use on every path (a value its grade
// uses once); exactly one use on every path that goes on (a value its type
// uses once); or exactly one giving up of its reference on every path that
// goes on, the uses that do not consume it not counting (a counted value).
enum class Rule : std::uint8_t { UsedAtMostOnce, UsedExactlyOnce, ConsumedExactlyOnce };

// Whether every use of a value counts under `rule`, or only those that
// consume its reference.
constexpr bool everyUse(Rule rule) { return rule != Rule::ConsumedExactlyOnce; }

// Whether `rule` asks for exactly one on every path that goes on, not at
// most one.
constexpr bool exactly(Rule rule) { return rule != Rule::UsedAtMostOnce; }

// Whether a path through a region goes on to what follows it, or ends the
// run first.
enum class Reach : std::uint8_t { GoesOn, EndsRun };

// One path's account of a value: where it goes, and the uses that count on
// it.
struct Account {
  Reach reach;
  unsigned uses;
};

// Whether an op's regions are alternatives, asked once per op class: a
// fact of the class, which every op of it shares.
class Exclusivity {
public:
  bool alternatives(Operation *op) {
    auto branch = dyn_cast<RegionBranchOpInterface>(op);
    if (!branch)
      return false;
    for (const auto &[name, answer] : asked)
      if (name == op->getName())
        return answer;
    bool answer = verify::alternatives(branch);
    asked.emplace_back(op->getName(), answer);
    return answer;
  }

private:
  SmallVector<std::pair<OperationName, bool>, 8> asked;
};

// Whether the last op of `block` ends the run: a terminator with no
// successor that returns to no op, is no return and breaks to no join
// point (a crash, an exit, an unreachable). A jump to a join point goes on,
// to the join point's region, which its op counts after it.
bool endsRun(Block &block) {
  if (block.empty())
    return false;
  Operation &last = block.back();
  return last.hasTrait<OpTrait::IsTerminator>() && last.getNumSuccessors() == 0 &&
         !isa<RegionBranchTerminatorOpInterface>(last) &&
         !last.hasTrait<OpTrait::ReturnLike>() && !isa<HasBreakingControlFlowOpInterface>(last);
}

// Whether region `index` of `op` may run more than once per run of `op`:
// a repeated region of a region branch, or any region of an op that says
// nothing of how its regions run.
bool repeated(Operation *op, unsigned index) {
  auto branch = dyn_cast<RegionBranchOpInterface>(op);
  return !branch || branch.isRepetitiveRegion(index);
}

// The count of one value under one rule.
class Count {
public:
  Count(Value value, Rule rule, Exclusivity &exclusivity)
      : value(value), rule(rule), exclusivity(exclusivity) {
    for (OpOperand &use : value.getUses())
      if (everyUse(rule) || consumes(use))
        users.push_back(use.getOwner());
  }

  LogicalResult check() {
    Block &home = *(isa<BlockArgument>(value) ? cast<BlockArgument>(value).getOwner()
                                              : value.getDefiningOp()->getBlock());
    // One use that counts, in the block that defines the value and in no
    // region below it: every path that goes on passes it, once.
    if (users.size() == 1 && users.front()->getBlock() == &home)
      return success();
    FailureOr<Account> account = accountOf(home);
    if (failed(account))
      return failure();
    if (!exactly(rule) || account->reach == Reach::EndsRun || account->uses == 1)
      return success();
    return emitError(value.getLoc())
           << (rule == Rule::UsedExactlyOnce
                   ? "is used once by its type and never used on a path that goes on"
                   : "holds a reference that is never given up on a path that goes on");
  }

private:
  // The uses that count which `op` makes itself.
  unsigned own(Operation *op) const { return llvm::count(users, op); }

  // Whether a use that counts lies inside `op`'s regions, or inside `region`.
  bool holds(Operation *op) const {
    return llvm::any_of(users, [&](Operation *user) { return user != op && op->isAncestor(user); });
  }
  bool holds(Region &region) const {
    return llvm::any_of(users,
                        [&](Operation *user) { return region.isAncestor(user->getParentRegion()); });
  }

  LogicalResult tooMany(Operation &op) {
    return op.emitOpError(everyUse(rule)
                              ? "uses a value used once that is already used on the same path"
                              : "gives up a reference already given up on the same path");
  }

  FailureOr<Account> accountOf(Block &block) {
    unsigned uses = 0;
    for (Operation &op : block) {
      uses += own(&op);
      if (op.getNumRegions() != 0 && holds(&op)) {
        FailureOr<Account> inner = accountOf(op);
        if (failed(inner))
          return failure();
        uses += inner->uses;
        if (uses > 1)
          return tooMany(op);
        if (inner->reach == Reach::EndsRun)
          return Account{Reach::EndsRun, uses};
      }
      if (uses > 1)
        return tooMany(op);
    }
    return Account{endsRun(block) ? Reach::EndsRun : Reach::GoesOn, uses};
  }

  // The regions of `op`, each a path or a part of one.
  FailureOr<Account> accountOf(Operation &op) {
    bool exclusive = exclusivity.alternatives(&op);
    SmallVector<Account, 4> each;
    for (Region &region : op.getRegions()) {
      Account account{Reach::GoesOn, 0};
      if (!region.empty() && holds(region)) {
        for (Block &block : region) {
          FailureOr<Account> inner = accountOf(block);
          if (failed(inner))
            return failure();
          account.uses += inner->uses;
          if (region.hasOneBlock())
            account.reach = inner->reach;
        }
      } else if (region.hasOneBlock() && endsRun(region.front())) {
        account.reach = Reach::EndsRun;
      }
      if (!exclusive && account.uses != 0 && repeated(&op, region.getRegionNumber()))
        account.uses *= 2;
      each.push_back(account);
    }
    if (!exclusive) {
      unsigned uses = 0;
      for (const Account &account : each)
        uses += account.uses;
      bool ends = !each.empty() && llvm::all_of(each, [](const Account &account) {
        return account.reach == Reach::EndsRun;
      });
      return Account{ends ? Reach::EndsRun : Reach::GoesOn, uses};
    }
    // Alternatives: one runs. A value used at most once is used at most as
    // often as the most any of them uses it; a value used or given up
    // exactly once is used as often on every alternative that goes on.
    std::optional<unsigned> goesOn;
    unsigned most = 0;
    for (const Account &account : each) {
      most = std::max(most, account.uses);
      if (account.reach == Reach::EndsRun)
        continue;
      if (exactly(rule) && goesOn && *goesOn != account.uses)
        return op.emitOpError(rule == Rule::UsedExactlyOnce
                                  ? "uses a value used once by its type on one alternative and not "
                                    "on another"
                                  : "gives up a reference on one alternative and not on another");
      goesOn = account.uses;
    }
    if (!exactly(rule))
      return Account{goesOn ? Reach::GoesOn : Reach::EndsRun, most};
    return Account{goesOn ? Reach::GoesOn : Reach::EndsRun, goesOn.value_or(0)};
  }

  Value value;
  Rule rule;
  Exclusivity &exclusivity;
  SmallVector<Operation *, 4> users;
};

} // namespace

LogicalResult idr::verify::linearity(FuncOp fn) {
  bool counted = stageFacts(fn.getProgram().getStage()).counted();
  Exclusivity exclusivity;
  auto checkValue = [&](Value value) -> LogicalResult {
    Type type = value.getType();
    if (counted && isa<idr::TokenType>(unrestricted(type)) && usesOf(type) == Uses::Many)
      return emitError(value.getLoc()) << "holds a reuse token at many uses";
    // A constant holds nothing a use could take: a folder materializes one
    // wherever it is needed, merges equal ones and hoists them out of
    // loops, so its uses repeat however the program was written.
    if (matchPattern(value, m_Constant()))
      return success();
    // Used once by its type: the type alone says so at every stage, and no
    // grade is written on it.
    if (isLinearByType(type))
      return Count(value, Rule::UsedExactlyOnce, exclusivity).check();
    if (usesOf(type) == Uses::Once &&
        failed(Count(value, Rule::UsedAtMostOnce, exclusivity).check()))
      return failure();
    if (!counted)
      return success();
    if (freedBy(type, Release::Counted) &&
        failed(Count(value, Rule::ConsumedExactlyOnce, exclusivity).check()))
      return failure();
    return success();
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
