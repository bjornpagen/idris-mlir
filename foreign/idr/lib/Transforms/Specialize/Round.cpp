// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-specialize: the specializer's one round over the whole program, just
// before idr-lifetimes, where every edge must become exact; and the one
// placement of a copy, which idr-optimize's schedule shares.
//
// After idr-optimize the e-graph still runs where the program holds our
// ops: as inline's simplification, and at the pipeline's simplify points
// after the columns and after bufferization. Each run stands a string or a
// big it computes at a call's argument as static data, as the call's rule
// lets a hold that fits its parameter's cross until the stage before
// counting, and nothing between those runs and that stage keys such a call.
// So here, once, each call that passes an operand at a hold its callee's
// parameter does not take is keyed by the one rule a signature key is made
// by (signatureOf), as a redirect of idr-optimize's rounds keys one: the
// copy is made of the callee as it stands, placed as idr-optimize places
// one, and the call calls it, its copy counting nothing of static data. A
// copy takes its parameter at that hold, so its body is re-graded and its
// own calls may pass the hold on: each copy is read in turn, after every
// function the program held whose calls cross, and a call that asks a key
// already made calls its copy. The keys are finitely many (holds, layout
// classes and result layouts are finite alphabets, and a size keys a copy
// only from a call outside its callee's cycle, the round reading no term of
// a body as its own), so the round ends by construction. Then each edge a
// value still crosses at a hold that fits the one asked (a call no key took,
// a literal yielded where a counted value is asked, a jump) is shared down
// (shareCrossings), and where a call calls a copy now, every row is written
// again over the graph frozen anew.
//
// The rule reads what each callee gives back: the identities solve, once,
// over the program's components callees first, on the bodies as they stand
// when the round begins; a copy gives back what its owner does, its
// parameters in their places. A call whose caller would read a result at
// more than the copy gives is not keyed (readsAsKeyed): no decision here
// takes its caller up again, so its argument crosses and is shared down. A
// key whose name a function of the program holds already, the copy
// idr-optimize made of it, is called only where that function still has
// the key's signature, which the end of idr-optimize's run narrows (an
// unread parameter, a dead result); elsewhere the argument crosses.

#include "idr/Analysis/Identities.h"
#include "idr/Analysis/Solver/ProgramGraph.h"
#include "idr/Analysis/Solver/Work.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/Support/Changed.h"
#include "idr/Support/Footprint.h"
#include "idr/Transforms/Effects.h"
#include "idr/Transforms/Specialize.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>
#include <cstdint>
#include <iterator>
#include <optional>

#define GEN_PASS_DEF_IDRSPECIALIZE
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/Passes.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::specialize {

using namespace detail;

FunctionId place(ProgramOp program, FuncOp anchor, FuncOp copy, solver::Editor &graph,
                 AnalysisManager am) {
  Block &body = program.getBody().front();
  Block::iterator at = std::next(Block::iterator(anchor.getOperation()));
  for (; at != body.end(); ++at) {
    auto next = dyn_cast<FuncOp>(*at);
    if (!next || !next.getSymName().starts_with(anchor.getSymName()) ||
        next.getSymName().compare(copy.getSymName()) >= 0)
      break;
  }
  body.getOperations().insert(at, copy.getOperation());
  FunctionId id = graph.insert(copy);
  graph.setCallees(id, solver::rowOf(copy, graph));
  (void)am.nest(copy);
  return id;
}

namespace {

// The signatures the round's keys give: a copy it makes has its key's, and
// no decision of a component restates one here.
struct KeyedCopies {
  FunctionType signatureOf(const SignatureKey *key) const { return key->signature; }
};
static_assert(KeySignatures<KeyedCopies>);

// What the round holds of each function by its id: the function; the one
// the program held whose call cycle it stands in, itself or, for a copy,
// its owner's; and what it gives back, a copy its owner's.
struct Held {
  FuncOp fn;
  FunctionId origin;
  identities::FactsView given;
};

// Whether `call` passes an operand at a hold its callee's parameter does not
// take.
bool crosses(CallOp call, FuncOp callee) {
  return llvm::any_of(passedHolds(call, callee.getArgumentTypes()),
                      [](const std::optional<Hold> &passed) { return passed.has_value(); });
}

// What the round did to the calls of the program.
struct Keyed {
  std::uint64_t copies = 0;
  std::uint64_t redirected = 0;
};

// Each call of a function of `frozen` that crosses, keyed and redirected to
// its copy, the copies read in turn; `frozen` thawed for the round and
// frozen again, its ids extended by the copies. A copy whose clone the
// key's edit cannot instantiate fails the round, as it fails idr-optimize's.
FailureOr<Keyed> keyCrossings(ProgramOp program, solver::ProgramGraph &frozen,
                             llvm::ArrayRef<FunctionId> crossing, AnalysisManager am,
                             solver::Work &work) {
  // What the editor does not hold, taken out before the graph thaws: each
  // function and its component, and the components callees first.
  footprint::Vector<Held> held;
  footprint::Vector<std::optional<solver::SccId>> cycleOf;
  for (FunctionId f : frozen.size().ids()) {
    held.push_back(Held{frozen.op(f), f, {}});
    cycleOf.push_back(frozen.op(f) ? std::optional(frozen.sccOf(f)) : std::nullopt);
  }
  footprint::Vector<footprint::Vector<solver::Member>> components;
  for (solver::SccId c : frozen.sccCount().ids()) {
    footprint::Vector<solver::Member> members;
    for (FunctionId f : frozen.members(c))
      members.push_back(solver::Member{f, frozen.op(f)});
    components.push_back(std::move(members));
  }
  solver::Editor editor = frozen.thaw();

  // What each function gives back, solved once, callees first, each
  // component reading its callees' as solved before it.
  footprint::Vector<identities::Facts> solved(held.size());
  for (const footprint::Vector<solver::Member> &members : components) {
    footprint::Vector<identities::Facts> given = identities::givesBackOf(
        editor, members, [&](FunctionId callee) { return solved[callee.index()].view(); }, work);
    for (auto [member, facts] : llvm::zip_equal(members, given))
      solved[member.id.index()] = std::move(facts);
  }
  for (auto [each, facts] : llvm::zip_equal(held, solved))
    each.given = facts.view();

  // Where a call stands to its callee's call cycle: inside it where the two
  // stand in one component, with no term of the caller's body read as its
  // own, so a size keys a copy only from outside the cycle.
  auto siteOf = [&](FunctionId self, FunctionId callee) -> CallSite {
    if (cycleOf[held[self.index()].origin.index()] == cycleOf[held[callee.index()].origin.index()])
      return InsideCycle{};
    return OutsideCycle{};
  };

  Arena arena;
  IRRewriter rewriter(program.getContext());
  Keyed done;
  footprint::Vector<FunctionId> queue(crossing.begin(), crossing.end());
  for (std::size_t next = 0; next < queue.size(); ++next) {
    FunctionId self = queue[next];
    FuncOp fn = held[self.index()].fn;
    // Where each call's results go, read off the function's tails once
    // before any redirect, which moves no other call's standing.
    SmallVector<CallOp> lost = lostTails(fn);
    SmallVector<CallOp> calls;
    fn.walk<WalkOrder::PreOrder>([&](CallOp call) { calls.push_back(call); });
    Changed redirected = Changed::No;
    for (CallOp call : calls) {
      FunctionId calleeId = editor.id(call.getCalleeAttr());
      Held callee = held[calleeId.index()];
      if (!crosses(call, callee.fn))
        continue;
      TailStanding standing =
          llvm::is_contained(lost, call) ? TailStanding::LostToLayout : TailStanding::Elsewhere;
      std::optional<SignatureWant> want =
          signatureOf(arena, KeyedCopies{}, call, callee.fn, calleeId, callee.given,
                      siteOf(self, calleeId), standing);
      if (!want)
        continue;
      const SignatureKey *key = want->key;
      auto name = FlatSymbolRefAttr::get(nameOf<Signatures>(callee.fn.getSymNameAttr(), key));
      // Essential: a function under the key's name is the copy of the key
      // idr-optimize made, which the end of its run may have narrowed, or
      // the one this round made; any other key is made here, once.
      if (std::optional<FunctionId> made = editor.find(name)) {
        if (held[made->index()].fn.getFunctionType() != key->signature)
          continue;
      } else {
        FailureOr<FuncOp> copy = makeCopy<Signatures>(callee.fn, key, name.getAttr());
        if (failed(copy))
          return failure();
        // A signature copy is none of the kinds of copy the inline verdict
        // weighs, whatever its owner was.
        copy->setCopy(std::nullopt);
        FunctionId id = place(program, callee.fn, *copy, editor, am);
        assert(id.index() == held.size() &&
               "the editor numbers each copy next, as the round holds it");
        held.push_back(Held{*copy, callee.origin, callee.given});
        queue.push_back(id);
        ++done.copies;
      }
      if (support::perform<SpecializeCloneAction>(call, [&] {
            redirect(rewriter, call, name, key->signature,
                     keptArgs(program.getContext(), call.getIndexArgsAttr(), key->indices),
                     SmallVector<Value>(call.getArgs()));
          })) {
        redirected = Changed::Yes;
        ++done.redirected;
      }
    }
    if (redirected == Changed::Yes)
      editor.setCallees(self, solver::rowOf(fn, editor));
  }
  std::move(editor).freeze();
  return done;
}

struct Round : impl::IdrSpecializeBase<Round> {
  void runOnProgram(ProgramOp program) {
    auto &graph = getAnalysis<solver::ProgramGraph>();
    // The functions a call of which crosses, in id order.
    SmallVector<FunctionId> crossing;
    for (FunctionId f : graph.functions())
      if (graph.op(f)
              .walk([&](CallOp call) {
                return crosses(call, graph.op(graph.id(call.getCalleeAttr())))
                           ? WalkResult::interrupt()
                           : WalkResult::advance();
              })
              .wasInterrupted())
        crossing.push_back(f);
    solver::Work work;
    Keyed done;
    if (!crossing.empty()) {
      FailureOr<Keyed> keyed = keyCrossings(program, graph, crossing, getAnalysisManager(), work);
      if (failed(keyed))
        return signalPassFailure();
      done = *keyed;
    }
    // Every edge still crossed is made exact, over the graph as the round
    // left it.
    Changed shared = Changed::No;
    for (FunctionId f : graph.functions())
      shared |= shareCrossings(graph.op(f), graph);
    numCopies += done.copies;
    numRedirected += done.redirected;
    if (done.copies == 0 && done.redirected == 0 && shared == Changed::No)
      return markAllAnalysesPreserved();
    // A call made of a copy holds its row and nothing of what the copy
    // leaves untouched or puts where: the writer derives every row and
    // record over the graph, and every call's copy of its callee's.
    if (done.redirected != 0)
      rows::write(program, graph, work);
    numWork += work.steps();
    markAnalysesPreserved<solver::ProgramGraph>();
  }
};

} // namespace

} // namespace idr::specialize
