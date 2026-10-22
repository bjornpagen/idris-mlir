// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// The one linearity rule, after every pass. A value used once by its grade's
// uses is used at most once on every path, field by field: a field read
// takes that field alone, as a match binds each field of its scrutinee
// once, and every other use takes the whole value, every field with it. A
// value used once by its type (a cell, a destination, a package) is used
// exactly once on every path that goes on: its one use is what takes it (an
// init fills the cell, a write fills the destination, an unpack reopens the
// package), so a path without it leaves memory nothing fills or gives
// back. Once the program is counted, a value that holds a reference of its
// own is given up exactly once on every path that goes on. All three are
// one count: the uses that count, on the worst path, the most over a
// match's alternatives, the sum over regions that run one after another,
// twice for a region that runs again. A path that ends the run (a crash,
// an exit) gives nothing up, since nothing after it runs. A value with one
// use that counts, in the block that defines it, is settled with no walk;
// only past one is a region looked into.
//
// Which regions of an op exclude each other is asked of
// RegionBranchOpInterface once per op class in one verify.

#include "idr/IR/Effects/Consumption.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Verify.h"

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
// uses once, of each field); exactly one use on every path that goes on (a
// value its type uses once); or exactly one giving up of its reference on
// every path that goes on, the uses that do not consume it not counting (a
// counted value).
enum class Rule : std::uint8_t { UsedAtMostOnce, UsedExactlyOnce, ConsumedExactlyOnce };

// Whether `rule` holds a value to its uses, or to the giving up of its
// reference.
constexpr bool everyUse(Rule rule) { return rule != Rule::ConsumedExactlyOnce; }

// Whether `rule` asks for exactly one on every path that goes on, not at
// most one.
constexpr bool exactly(Rule rule) { return rule != Rule::UsedAtMostOnce; }

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

// The count of one value under one rule, of the uses `counts` takes.
class Count {
public:
  template <UseFilter Counts>
  Count(Value value, Rule rule, Exclusivity &exclusivity, Counts &&counts)
      : value(value), rule(rule), exclusivity(exclusivity) {
    for (OpOperand &use : value.getUses())
      if (counts(use))
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

  // The account of `home`'s ops, each op whose regions hold a use looked
  // into: the blocks and the region ops still being counted wait on a list,
  // never on the C++ stack, so a deep nest of regions costs memory, not
  // native frames. Each step returns its account to the one below it.
  FailureOr<Account> accountOf(Block &home) {
    // A block whose ops are being counted, and the op whose regions it
    // waits on.
    struct InBlock {
      Block *block;
      Block::iterator next;
      unsigned uses;
      Operation *waiting;
    };
    // An op whose regions are being counted: the region now and its block,
    // whether that region is being looked into, its account so far, and
    // each finished region's.
    struct InRegions {
      Operation *op;
      bool exclusive;
      unsigned region;
      Region::iterator block;
      bool lookedInto;
      Account account;
      SmallVector<Account, 4> each;
    };
    SmallVector<std::variant<InBlock, InRegions>, 8> steps;
    steps.push_back(InBlock{&home, home.begin(), 0, nullptr});
    std::optional<Account> returned;
    for (;;) {
      if (auto *in = std::get_if<InBlock>(&steps.back())) {
        if (returned) {
          Operation &op = *in->waiting;
          Account inner = *std::exchange(returned, std::nullopt);
          in->uses += inner.uses;
          if (in->uses > 1)
            return tooMany(op);
          if (inner.reach == Reach::EndsRun) {
            Account done{Reach::EndsRun, in->uses};
            steps.pop_back();
            if (steps.empty())
              return done;
            returned = done;
            continue;
          }
        }
        if (in->next == in->block->end()) {
          Account done{endsRun(*in->block) ? Reach::EndsRun : Reach::GoesOn, in->uses};
          steps.pop_back();
          if (steps.empty())
            return done;
          returned = done;
          continue;
        }
        Operation &op = *in->next++;
        in->uses += own(&op);
        if (op.getNumRegions() != 0 && holds(&op)) {
          in->waiting = &op;
          steps.push_back(InRegions{&op, exclusivity.alternatives(&op), 0, {}, false,
                                    Account{Reach::GoesOn, 0}, {}});
          continue;
        }
        if (in->uses > 1)
          return tooMany(op);
        continue;
      }

      auto &at = std::get<InRegions>(steps.back());
      if (returned) {
        Account inner = *std::exchange(returned, std::nullopt);
        at.account.uses += inner.uses;
        if (at.op->getRegion(at.region).hasOneBlock())
          at.account.reach = inner.reach;
        ++at.block;
      }
      if (at.region < at.op->getNumRegions()) {
        Region &region = at.op->getRegion(at.region);
        if (!at.lookedInto && !region.empty() && holds(region)) {
          at.lookedInto = true;
          at.block = region.begin();
        } else if (!at.lookedInto && region.hasOneBlock() && endsRun(region.front())) {
          at.account.reach = Reach::EndsRun;
        }
        if (at.lookedInto && at.block != region.end()) {
          Block &block = *at.block;
          steps.push_back(InBlock{&block, block.begin(), 0, nullptr});
          continue;
        }
        // The region is counted: twice if it runs again, beside regions
        // that run one after another.
        if (!at.exclusive && at.account.uses != 0 && repeated(at.op, at.region))
          at.account.uses *= 2;
        at.each.push_back(at.account);
        ++at.region;
        at.lookedInto = false;
        at.account = Account{Reach::GoesOn, 0};
        continue;
      }
      FailureOr<Account> done = combined(*at.op, at.exclusive, at.each);
      if (failed(done))
        return failure();
      steps.pop_back();
      returned = *done;
    }
  }

  // The account of an op from its regions' accounts, `each`: the sum over
  // regions that run one after another; over alternatives, one runs.
  FailureOr<Account> combined(Operation &op, bool exclusive, ArrayRef<Account> each) {
    if (!exclusive) {
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

// Every use counts.
bool anyUse(OpOperand &) { return true; }

// Whether `use` takes field `index` of the value it uses: a field read
// takes the field it reads and no other; every other use takes the whole
// value, and every field with it.
bool takesField(OpOperand &use, std::uint64_t index) {
  auto read = dyn_cast<DataFieldOp>(use.getOwner());
  return !read || read.getIndex() == index;
}

// A value its grade uses once is used at most once on every path, field by
// field: each field some use reads is counted with the uses that take the
// whole value, so a field read twice, or read beside a use of the whole, is
// a second use of it. A value no use reads a field of is counted whole.
LogicalResult usedAtMostOnceEachField(Value value, Exclusivity &exclusivity) {
  SmallVector<std::uint64_t, 4> read;
  for (Operation *user : value.getUsers())
    if (auto field = dyn_cast<DataFieldOp>(user);
        field && !llvm::is_contained(read, field.getIndex()))
      read.push_back(field.getIndex());
  if (read.empty())
    return Count(value, Rule::UsedAtMostOnce, exclusivity, anyUse).check();
  for (std::uint64_t index : read)
    if (failed(Count(value, Rule::UsedAtMostOnce, exclusivity,
                     [index](OpOperand &use) { return takesField(use, index); })
                   .check()))
      return failure();
  return success();
}

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
      return Count(value, Rule::UsedExactlyOnce, exclusivity, anyUse).check();
    if (usesOf(type) == Uses::Once && failed(usedAtMostOnceEachField(value, exclusivity)))
      return failure();
    if (!counted)
      return success();
    if (freedBy(type, Release::Counted) &&
        failed(Count(value, Rule::ConsumedExactlyOnce, exclusivity,
                     [](OpOperand &use) { return effects::consumes(use); })
                   .check()))
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
