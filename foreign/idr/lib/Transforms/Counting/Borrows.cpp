// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-rc-borrows: borrow inference's answer (idr/Analysis/Ownership.h)
// written into the program, once, before placement reads the holds. A
// parameter, of a function or of a join point, that the inference makes a
// view of its caller's value is graded `scoped`, with what it claimed of
// its sharing; so is every value read from it, since a value read from a
// view is a view: what hands it on at another grade (a cast, a share), a
// part read of it (a field, a view of its buffer), what a region binds it
// as (a case's refined scrutinee) and what a region gives out of it. Then
// each call or jump that passes a counted value where a view is now asked
// lends it (`idr.lend`) around the call, or around the join point the jump
// enters: the value comes back from the loan as the same value, so every
// use after the loan reads what the loan gives back, and a view cannot be
// read once its owner is dropped.
//
// The inference lends only an argument something still needs after the
// call, or one whose type bounds what it reaches at a call that returns, so
// no loan wraps a call in tail position, and the owner of a jump's loan is
// used after the join point and so made before it. A loan that would break
// either is the inference's promise broken, an internal error; a view that
// meets a slot the inference left counted fails the verifier where it
// stands. Nor does it lend where the loan would wrap a call on its
// function's own cycle, directly or in a join point, since frames split
// such a call's function into a frame per level and no loan's region can be
// split: there the argument's parameter is counted, as a parameter's grade
// is one for every caller, and the value is passed owned.
#include "idr/Analysis/Ownership.h"
#include "idr/Analysis/Ownership/Walks.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Lifetimes.h"
#include "idr/IR/Ownership.h"
#include "idr/Transforms/Counting.h"
#include "idr/Transforms/Counting/Facts.h"
#include "idr/Transforms/Pipeline.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/BuiltinTypes.h"
#include "mlir/Interfaces/ControlFlowInterfaces.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallBitVector.h"

#include <vector>

namespace idr {
#define GEN_PASS_DEF_IDRRCBORROWS
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::counting {
namespace {

using solver::FunctionId;

// `type` as a view: freed by its lifetime, claiming what it claimed.
Type asView(Type type) { return atHold(type, Hold::scoped(holdOf(type)->claim())); }

// A loan to make: the counted `owner` lent around `site`, its view given at
// each of `positions`, operands of `site` or of ops in it.
struct Loan {
  Operation *site;
  Value owner;
  SmallVector<OpOperand *, 2> positions;
};

class Writer {
public:
  Writer(const solver::ProgramGraph &graph, const Borrows &borrows)
      : graph(graph), borrows(borrows),
        viewed(graph.table<llvm::SmallBitVector>()) {}

  LogicalResult run();

  unsigned numLoans = 0;

private:
  void decide();
  void writeSignatures();
  void spread();
  void reach(Value next);
  void reachSuccessor(RegionBranchOpInterface target, const RegionSuccessor &successor,
                      unsigned index);
  LogicalResult findLoans(FunctionId fn, SmallVectorImpl<Loan> &loans);
  LendOp lend(const Loan &loan);

  // Adds `position` to the loan of `owner` around `site`, made once.
  static void addLoan(SmallVectorImpl<Loan> &loans, Operation *site, OpOperand &position) {
    Value owner = position.get();
    for (Loan &loan : loans)
      if (loan.site == site && loan.owner == owner) {
        loan.positions.push_back(&position);
        return;
      }
    loans.push_back(Loan{site, owner, {&position}});
  }

  const solver::ProgramGraph &graph;
  const Borrows &borrows;
  // Per function, the parameters the inference made views.
  IndexVector<FunctionId, llvm::SmallBitVector> viewed;
  // The join parameters it made views, of every function.
  SmallVector<BlockArgument> viewedJoins;
  // The values made views whose readers are still to be retyped: the
  // retyped type is the mark, so each value is met once.
  std::vector<Value> pending;
};

LogicalResult Writer::run() {
  decide();
  writeSignatures();
  spread();
  for (FunctionId fn : graph.functions()) {
    SmallVector<Loan> loans;
    if (failed(findLoans(fn, loans)))
      return failure();
    // A site that lends two values is lent again from outside: the later
    // loans of the site wrap the loan just made.
    for (std::size_t at = 0; at < loans.size(); ++at) {
      Operation *site = loans[at].site;
      LendOp made = lend(loans[at]);
      for (std::size_t later = at + 1; later < loans.size(); ++later)
        if (loans[later].site == site)
          loans[later].site = made;
    }
  }
  return success();
}

// The inference's answer, read for every function before anything is
// rewritten, so the join parameters are numbered on the bodies it read.
void Writer::decide() {
  for (FunctionId fn : graph.functions()) {
    FuncOp op = graph.op(fn);
    Block &entry = op.getBody().front();
    llvm::SmallBitVector &bits = viewed[fn];
    bits.resize(entry.getNumArguments());
    for (BlockArgument param : entry.getArguments())
      if (isCountedValue(param.getType()) &&
          borrows.parameter(fn, param.getArgNumber()) == Release::Scoped)
        bits.set(param.getArgNumber());
    borrows::forEachJoinParameter(op, [&](BlockArgument arg, std::uint32_t index) {
      if (isCountedValue(arg.getType()) && borrows.joinParameter(fn, index) == Release::Scoped)
        viewedJoins.push_back(arg);
    });
  }
}

// Each view parameter retyped where it is bound and in its function's
// signature, the results untouched: a result is never a view.
void Writer::writeSignatures() {
  for (FunctionId fn : graph.functions()) {
    const llvm::SmallBitVector &bits = viewed[fn];
    if (bits.none())
      continue;
    FuncOp op = graph.op(fn);
    Block &entry = op.getBody().front();
    for (int at = bits.find_first(); at >= 0; at = bits.find_next(at))
      reach(entry.getArgument(static_cast<unsigned>(at)));
    op.setFunctionType(FunctionType::get(op.getContext(), entry.getArgumentTypes(),
                                         op.getFunctionType().getResults()));
  }
  for (BlockArgument arg : viewedJoins)
    reach(arg);
}

// `next`, read from a view, is a view, unless it holds nothing its count
// frees (a buffer's elements, static data) or is a view already.
void Writer::reach(Value next) {
  if (!isCountedValue(next.getType()))
    return;
  next.setType(asView(next.getType()));
  pending.push_back(next);
}

// The input `index` of `successor` of `target`, which a value made a view
// flows into: retyped, unless it is a join parameter, whose hold the
// inference decided for every jump into it.
void Writer::reachSuccessor(RegionBranchOpInterface target, const RegionSuccessor &successor,
                            unsigned index) {
  ValueRange inputs = target.getSuccessorInputs(successor);
  if (index >= inputs.size())
    return;
  Value input = inputs[index];
  if (auto arg = dyn_cast<BlockArgument>(input); arg && borrows::isJoinParameter(arg))
    return;
  reach(input);
}

// Every value read from a view, retyped a view: one forward walk over uses,
// its stack on the heap.
void Writer::spread() {
  while (!pending.empty()) {
    Value view = pending.back();
    pending.pop_back();
    for (OpOperand &use : view.getUses()) {
      Operation *user = use.getOwner();
      unsigned number = use.getOperandNumber();
      if (number == 0 && user->hasTrait<ResultCarriesOperand>())
        reach(user->getResult(0));
      // An element read out of the view's buffer is read from it too, but
      // stays counted: placement lends it while nothing may overwrite it,
      // and gives it a reference of its own where it is read otherwise. A
      // read its op makes fresh (a field re-packed into a fresh cell or
      // array) holds what it holds on its own, so it is no view either.
      for (Value result : user->getResults())
        if (ownership::readFrom(result) == view && readWithoutReference(result) &&
            !elementBufferOf(result))
          reach(result);
      if (auto branch = dyn_cast<RegionBranchOpInterface>(user)) {
        SmallVector<RegionSuccessor> entries;
        branch.getSuccessorRegions(RegionBranchPoint::parent(), entries);
        for (const RegionSuccessor &entry : entries) {
          OperandRange forwarded = branch.getEntrySuccessorOperands(entry);
          if (forwarded.empty())
            continue;
          unsigned first = forwarded.getBeginOperandIndex();
          if (number >= first && number < first + forwarded.size())
            reachSuccessor(branch, entry, number - first);
        }
      }
      if (auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(user)) {
        SmallVector<Attribute> constants(user->getNumOperands());
        SmallVector<RegionSuccessor> successors;
        terminator.getSuccessorRegions(constants, successors);
        for (const RegionSuccessor &successor : successors) {
          OperandRange forwarded = terminator.getSuccessorOperands(successor);
          if (forwarded.empty())
            continue;
          unsigned first = forwarded.getBeginOperandIndex();
          if (number < first || number >= first + forwarded.size())
            continue;
          Operation *target = successor.isOperation() ? successor.getSuccessorOp()
                                                      : successor.getSuccessor()->getParentOp();
          reachSuccessor(cast<RegionBranchOpInterface>(target), successor, number - first);
        }
      }
    }
  }
}

// The loans `fn` needs: a call that passes a counted value to a parameter
// its callee takes as a view lends it around the call; a jump that passes
// one to a join parameter made a view lends it around the join point.
LogicalResult Writer::findLoans(FunctionId fn, SmallVectorImpl<Loan> &loans) {
  FuncOp op = graph.op(fn);
  LogicalResult found = success();
  op.walk([&](Operation *at) {
    if (auto call = dyn_cast<CallOp>(at)) {
      const llvm::SmallBitVector &bits = viewed[graph.id(call.getCalleeAttr())];
      for (OpOperand &operand : call->getOpOperands()) {
        unsigned index = operand.getOperandNumber();
        if (index >= bits.size() || !bits.test(index) || !isCountedValue(operand.get().getType()))
          continue;
        if (call.getTailKind() != TailKind::nontail) {
          found = call.emitOpError("internal error: borrowing lends argument ")
                  << index << " of a call in tail position, which nothing may follow";
          return WalkResult::interrupt();
        }
        addLoan(loans, call, operand);
      }
      return WalkResult::advance();
    }
    auto terminator = dyn_cast<RegionBranchTerminatorOpInterface>(at);
    if (!terminator)
      return WalkResult::advance();
    SmallVector<Attribute> constants(at->getNumOperands());
    SmallVector<RegionSuccessor> successors;
    terminator.getSuccessorRegions(constants, successors);
    for (const RegionSuccessor &successor : successors) {
      if (successor.isOperation())
        continue;
      Operation *join = successor.getSuccessor()->getParentOp();
      ValueRange inputs = cast<RegionBranchOpInterface>(join).getSuccessorInputs(successor);
      OperandRange forwarded = terminator.getSuccessorOperands(successor);
      if (forwarded.empty())
        continue;
      unsigned first = forwarded.getBeginOperandIndex();
      for (auto [index, input] : llvm::enumerate(inputs)) {
        if (index >= forwarded.size())
          break;
        OpOperand &position = at->getOpOperand(first + static_cast<unsigned>(index));
        auto arg = dyn_cast<BlockArgument>(input);
        if (!arg || !freedBy(arg.getType(), Release::Scoped) || !borrows::isJoinParameter(arg) ||
            !isCountedValue(position.get().getType()))
          continue;
        if (join->isAncestor(position.get().getParentBlock()->getParentOp())) {
          found = at->emitOpError("internal error: borrowing lends a value made inside the join "
                                  "point its jump enters, which no loan around it can hold");
          return WalkResult::interrupt();
        }
        addLoan(loans, join, position);
      }
    }
    return WalkResult::advance();
  });
  return found;
}

// The loan: `site` moves into the loan's region, each position takes the
// view, the site's results leave through the loan's, and every use of the
// owner after the loan reads the owner it gives back.
LendOp Writer::lend(const Loan &loan) {
  Operation *site = loan.site;
  Value owner = loan.owner;
  Location loc = site->getLoc();
  OpBuilder b(site);
  auto made = LendOp::create(b, loc, owner.getType(), site->getResultTypes(), owner, ValueRange());
  Type lifetime = LifetimeType::get(site->getContext(), LifetimeKind::view());
  Type view = graded(Grade{Uses::Many, Hold::scoped(holdOf(owner.getType())->claim())}, owner.getType());
  Block *body = b.createBlock(&made.getBody(), {}, {lifetime, view}, {loc, loc});
  site->replaceAllUsesWith(made->getResults().drop_front());
  site->moveBefore(body, body->end());
  for (OpOperand *position : loan.positions)
    position->set(body->getArgument(1));
  b.setInsertionPointToEnd(body);
  YieldOp::create(b, loc, site->getResults());
  Block *block = made->getBlock();
  owner.replaceUsesWithIf(made.getReturned(), [&](OpOperand &use) {
    Operation *at = block->findAncestorOpInBlock(*use.getOwner());
    return at && at != made && made->isBeforeInBlock(at);
  });
  ++numLoans;
  return made;
}

struct RcBorrows : impl::IdrRcBorrowsBase<RcBorrows> {
  void runOnProgram(ProgramOp) {
    const solver::ProgramGraph &graph = getAnalysis<solver::ProgramGraph>();
    const Borrows &borrows = getAnalysis<Borrows>();
    Writer writer(graph, borrows);
    if (failed(writer.run()))
      return signalPassFailure();
    numViews += borrows.views();
    numLoans += writer.numLoans;
  }
};

} // namespace
} // namespace idr::counting
