// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Unread parameters, dropped when their function's component becomes
// final, before any caller outside it is taken up: what no callee reads of
// a parameter is a bit of its summary, decided where the callee becomes
// final, so no state per value of the program exists to run out of.
//
// A parameter is read unless every use of it passes it to a parameter of a
// member of its own component that is unread in turn: a least fixpoint
// over the component's parameters, whose bits only rise, so it ends by
// construction. A callee outside the component is final, its unread
// parameters dropped already, so whatever it still takes it reads. Only a
// parameter used many times can be unread: Idris checked that a parameter
// of quantity one is used. The program's root keeps its signature, since
// it is called from outside, and so does a function a family's label names
// here: its leading parameters are that label's captures, and dropping one
// drops its constructor's field, which declares the family anew in every
// type of the program, so the end of the run drops them all at once
// (Captures.cpp).
//
// Every caller outside the component is waiting, not taken up: a function
// is taken up only once every component it calls into is final. So the
// calls of a member are its component's and those its callers' rows list,
// and each loses its operands at the dropped positions here, between
// waves, where no turn runs.

#include "idr/IR/IdrDialect.h"
#include "idr/Transforms/OptimizeScheduler.h"

#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/Sequence.h"
#include "llvm/ADT/STLExtras.h"

using namespace mlir;

namespace idr::optimize {

namespace {

// A parameter of a member, by the member's position in the component and
// the parameter's.
struct Param {
  unsigned member;
  unsigned index;
};

} // namespace

void dropUnread(Schedule &schedule, ArrayRef<FunctionId> ids) {
  StringAttr root = schedule.program.getRootAttr().getAttr();
  SmallVector<FuncOp> fns = llvm::map_to_vector(ids, [&](FunctionId id) { return schedule.function(id); });
  // A callee's place among the members, by the program's one numbering of
  // its functions: the members are in id order; none for a function of
  // another component.
  auto memberAt = [&](CallOp call) -> std::optional<unsigned> {
    std::optional<FunctionId> callee = schedule.graph.find(call.getCalleeAttr());
    if (!callee)
      return std::nullopt;
    const FunctionId *at = llvm::lower_bound(ids, *callee);
    if (at == ids.end() || *at != *callee)
      return std::nullopt;
    return static_cast<unsigned>(at - ids.begin());
  };
  // Whether each member may lose a parameter at all.
  auto narrowable = [&](unsigned at) {
    return fns[at].getSymNameAttr() != root && !schedule.isLabel(ids[at]);
  };

  // `read[m][p]`: whether parameter p of member m is read. Seeded by every
  // use that is no call of a member, and by every parameter of a member
  // that may not lose one; each read parameter then makes read every
  // parameter of a member whose value reaches it at a call.
  SmallVector<llvm::BitVector> read;
  SmallVector<SmallVector<SmallVector<Param, 1>>> feeds;
  SmallVector<Param> work;
  for (auto [at, fn] : llvm::enumerate(fns)) {
    unsigned arity = fn.getNumArguments();
    read.emplace_back(arity);
    feeds.emplace_back(arity);
  }
  for (auto [at, fn] : llvm::enumerate(fns)) {
    auto m = static_cast<unsigned>(at);
    for (BlockArgument param : fn.getArguments()) {
      unsigned p = param.getArgNumber();
      bool seed = !narrowable(m) || isLinear(param.getType());
      for (OpOperand &use : param.getUses()) {
        auto call = dyn_cast<CallOp>(use.getOwner());
        std::optional<unsigned> callee = call ? memberAt(call) : std::nullopt;
        if (!callee) {
          seed = true;
          continue;
        }
        unsigned q = use.getOperandNumber() - call.getArgs().getBeginOperandIndex();
        // Parameter q of the callee being read makes this one read.
        feeds[*callee][q].push_back(Param{m, p});
      }
      if (seed) {
        read[m].set(p);
        work.push_back(Param{m, p});
      }
    }
  }
  while (!work.empty()) {
    Param at = work.pop_back_val();
    for (Param fed : feeds[at.member][at.index])
      if (!read[fed.member].test(fed.index)) {
        read[fed.member].set(fed.index);
        work.push_back(fed);
      }
  }

  // The calls of each member that loses a parameter, in its component and
  // in its callers, lose their operands first, every member's before any
  // parameter goes: an unread parameter's last uses are operands at the
  // dropped positions of its component's calls.
  SmallVector<llvm::BitVector> unread;
  SmallVector<SmallVector<CallOp>> narrowed(fns.size());
  for (auto [at, fn] : llvm::enumerate(fns)) {
    llvm::BitVector bits = read[at];
    bits.flip();
    unread.push_back(bits);
    if (bits.none())
      continue;
    StringAttr name = fn.getSymNameAttr();
    auto narrow = [&](FuncOp caller) {
      caller.getBody().walk([&](CallOp call) {
        if (call.getCalleeAttr().getAttr() != name)
          return;
        llvm::BitVector operands(call->getNumOperands());
        for (unsigned p : bits.set_bits())
          operands.set(call.getArgs().getBeginOperandIndex() + p);
        call->eraseOperands(operands);
        narrowed[at].push_back(call);
      });
    };
    for (FuncOp member : fns)
      narrow(member);
    for (FunctionId caller : schedule.callersOf(ids[at]))
      if (!llvm::is_contained(ids, caller))
        narrow(schedule.function(caller));
  }
  // The parameters go, with what the signature states of them, then each
  // call takes its callee's statements again; and the binding times the
  // turn solved for them go.
  for (auto [id, fn, bits, calls] : llvm::zip_equal(ids, fns, unread, narrowed)) {
    if (bits.none())
      continue;
    (void)fn.eraseArguments(bits);
    for (CallOp call : calls)
      call.copyCallee(fn);
    idr::match(
        schedule.members[id.index()].phase,
        [&](Done &done) {
          // A parameter's position is its bit's, which a bit vector
          // numbers as it numbers its bits.
          SmallVector<BindingTime> kept;
          for (unsigned p : llvm::seq(0u, bits.size()))
            if (!bits.test(p))
              kept.push_back(done.solved.times[p]);
          done.solved.times = std::move(kept);
        },
        [](OneOf<Waiting, Parked, Final> auto &) {});
  }
}

} // namespace idr::optimize
