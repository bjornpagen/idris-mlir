// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// idr-redirect: the step of idr-optimize's inner pipeline that requests,
// for each call of a function, the copy its key names, and calls it.
//
// It runs first in each round of a member, so that a combinator called on
// known closures is a call of its copy for those closures before the
// e-graph sees the member: the laws of a combinator tower are known-case
// folds inside the copy, which a simplification of the caller alone could
// never reach. A call's callee is read only once it is final, or where it
// is of the member's own component and the call applies closures built for
// it alone (the beta step of a recursion), as the member's turn left it.

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Tail.h"
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

#include <cassert>

#define GEN_PASS_DEF_IDRREDIRECT
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/InnerPasses.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::specialize {

using namespace detail;

CallSite detail::siteOf(const optimize::Schedule &schedule, FunctionId self, const Node *node,
                        FunctionId callee) {
  FunctionId theirs = schedule.originOf(callee);
  auto inside = [&](FunctionId cycle) { return schedule.sameComponent(cycle, theirs); };
  if (!node)
    return inside(schedule.originOf(self)) ? CallSite(InsideCycle{}) : CallSite(OutsideCycle{});
  if (llvm::any_of(node->cycles, inside))
    return InsideCycle{node->own};
  return OutsideCycle{};
}

IndexArgsAttr detail::keptArgs(MLIRContext *ctx, IndexArgsAttr call, IndexArgsAttr classes) {
  if (!call)
    return call;
  SmallVector<families::TermNode> kept;
  std::uint64_t count = 0;
  ArrayRef<families::TermNode> mine = call.getTerms(), theirs = classes.getTerms();
  while (!mine.empty()) {
    families::Term own(mine), fixed(theirs);
    assert((fixed.isClosed() || fixed.kind() == TermKind::Level) &&
           "a copy's key fixes a binder to a closed term or keeps it as a level");
    if (fixed.kind() == TermKind::Level) {
      assert(fixed.head().value == count && "a copy keeps a binder as its next level");
      llvm::append_range(kept, own.nodes());
      ++count;
    }
    mine = mine.drop_front(own.nodes().size());
    theirs = theirs.drop_front(fixed.nodes().size());
  }
  return IndexArgsAttr::get(ctx, kept, count);
}

namespace {

// The binding times of a callee's parameters as a call sees them: within
// the recursion of the cycle both stand in, the callee's own; entering it
// from outside, each is fixed. The callee is read through a const reference,
// so its handle is copied out, as an op is passed.
SmallVector<BindingTime> seenBy(const CallSite &site, const optimize::Readable &read) {
  FuncOp callee = read.fn;
  return idr::match(
      site, [&](const InsideCycle &) { return SmallVector<BindingTime>(read.times); },
      [&](OutsideCycle) {
        return SmallVector<BindingTime>(callee.getNumArguments(), BindingTime::Fixed);
      });
}

// The type of the copy a grant names, known from the key before the copy
// is built: a pattern copy takes its key's holes and returns its owner's
// results; a signature copy has its key's signature, static at each bare
// tensor argument's axis the call's index arguments make a constant; a
// raise copy takes the call's operands and the consumer's free values and
// returns what the consumer's function, the form its key names, returns:
// what the dispatch gives, `?` at every axis of an array.
FunctionType typeOf(const Nodes::Grant &grant, FuncOp owner, const Want &want,
                    const Forms &forms) {
  return idr::match(
      want,
      [&](const PatternWant &) {
        SmallVector<Type> holes;
        for (auto [pattern, type] : llvm::zip_equal(grant.key->params, owner.getArgumentTypes()))
          holeTypes(*pattern, type, holes);
        return FunctionType::get(owner.getContext(), holes, owner.getResultTypes());
      },
      [](const SignatureWant &copy) { return copy.key->signature; },
      [&](const RaiseWant &raise) {
        return FunctionType::get(owner.getContext(), ValueRange(raise.operands).getTypes(),
                                 forms.at(raise.key->form).getResultTypes());
      });
}

// What `call`, redirected to the copy `made`, the node a granted key names
// (none for one the table has not made yet), passes, from the key's
// signature `type` and the operands the key would pass, which become those
// it passes. Where the decisions of the component the copy joined restated
// its signature, the call is made at theirs (Node::signature): its results
// as they left them, which a signature key's want was judged against
// (signatureOf; a pattern or raise key whose copy's results they changed
// is not granted), and its parameters at the holds that component passes:
// an operand that claims more than one is shared down to it before the
// call, as every call of a lowered parameter is, a claim no key may raise;
// one that differs otherwise (static data where the copy counts) crosses
// at the copy's hold until the copy is final and its own copy is keyed to
// it, or the caller's edges are made exact. Then each but those at the
// parameters the node says its copy no longer takes, which dropUnread
// erased when the copy's component became final. A copy not final yet
// takes them all; a call of it made now loses them with its callers' when
// it is.
FunctionType passing(CallOp call, const Node *made, FunctionType type,
                     SmallVectorImpl<Value> &operands) {
  if (made)
    idr::match(
        made->restated, [](AsKeyed) {},
        [&](const OneOf<ParametersLowered, ResultsChanged> auto &restated) {
          type = restated.type;
          OpBuilder b(call);
          for (auto [operand, input] : llvm::zip_equal(operands, type.getInputs())) {
            std::optional<Hold> given = holdOf(operand.getType());
            std::optional<Hold> asked = holdOf(input);
            if (given && asked && given->claim() != asked->claim() && given->fits(*asked))
              operand = heldAs(b, call.getLoc(), operand, atHold(operand.getType(), *asked));
          }
        });
  if (!made || made->unread.none())
    return type;
  assert(made->unread.size() == operands.size() &&
         "a copy's unread parameters are positions of its key's signature");
  SmallVector<Type> inputs;
  SmallVector<Value> kept;
  for (unsigned position = 0, end = static_cast<unsigned>(operands.size()); position < end;
       ++position)
    if (!made->unread.test(position)) {
      inputs.push_back(type.getInput(position));
      kept.push_back(operands[position]);
    }
  operands.assign(kept.begin(), kept.end());
  return FunctionType::get(type.getContext(), inputs, type.getResults());
}

// The calls the step at `place` in `self`'s round decides, in walk order:
// every call, first; last, none where the round goes on anyway (it asked
// for a copy or inlined a leaf, so the next round's first step decides
// every call), and otherwise each call of a final callee that passes an
// operand at a hold its parameter does not take, which the first step
// keyed, or found refused, at the hold it was passed then.
SmallVector<CallOp> callsDecided(FuncOp fn, optimize::Schedule &schedule, FunctionId self,
                                 InRound place) {
  SmallVector<CallOp> calls;
  if (place == InRound::First) {
    fn.walk<WalkOrder::PreOrder>([&](CallOp call) { calls.push_back(call); });
    return calls;
  }
  if (schedule.requesterOf(self).asks() || schedule.inlinedLeaves(self))
    return calls;
  fn.walk<WalkOrder::PreOrder>([&](CallOp call) {
    std::optional<FunctionId> callee = schedule.graph.find(call.getCalleeAttr());
    if (!callee)
      return;
    if (std::optional<optimize::Readable> known = schedule.final(*callee);
        known && llvm::any_of(passedHolds(call, known->fn.getArgumentTypes()),
                              [](const std::optional<Hold> &passed) { return passed.has_value(); }))
      calls.push_back(call);
  });
  return calls;
}

// Each call of `fn` its step decides (callsDecided) in walk order: its want
// decided, its key requested, and the call made a call of the granted copy.
// How many calls it redirected; a failure is an internal error, emitted.
//
// The calls are numbered by their place in the one walk. A raise erases
// the dispatch it moves into the copy, later in the call's block, and
// every call inside it, which the walk has not met yet; no other redirect
// erases a call but its own. So before a raise, each call still to come
// that the dispatch holds is marked by its number, and the walk passes it.
//
// Where each call's results go is read once, off the function's tails
// before any redirect. A redirect touches its own call, the ops that built
// its arguments and the uses of its results; a raise, the ops from its call
// to the dispatch, which its call replaces. Any such op on another call's
// way to the return has a call or a use of one's results on that way too,
// before the edit and after, so that call was no tail and is none: no
// other call's standing moves.
FailureOr<unsigned> redirectCalls(FuncOp fn, optimize::Schedule &schedule, Nodes &nodes,
                                  InRound place) {
  FunctionId self = schedule.graph.id(FlatSymbolRefAttr::get(fn.getSymNameAttr()));
  Requester &asking = schedule.requesterOf(self);
  const Node *requester = nodes.find(self);
  SmallVector<CallOp> calls = callsDecided(fn, schedule, self, place);
  if (calls.empty())
    return 0u;
  SmallVector<CallOp> lost = lostTails(fn);
  auto standingOf = [&](CallOp call) {
    return llvm::is_contained(lost, call) ? TailStanding::LostToLayout : TailStanding::Elsewhere;
  };
  auto count = static_cast<unsigned>(calls.size());
  llvm::BitVector erased(count);
  IRRewriter rewriter(fn.getContext());
  unsigned redirected = 0;
  for (unsigned at = 0; at < count; ++at) {
    if (erased.test(at))
      continue;
    CallOp call = calls[at];
    // A call of a copy made in this wave names no function of the schedule
    // until the wave ends: it is pending, and nothing is read of it.
    std::optional<FunctionId> callee = schedule.graph.find(call.getCalleeAttr());
    if (!callee)
      continue;
    FailureOr<std::optional<Want>> want = std::optional<Want>();
    if (std::optional<optimize::Readable> known = schedule.final(*callee)) {
      CallSite site = siteOf(schedule, self, requester, *callee);
      want = decide(nodes, call, requester, known->fn, *callee, nodes.find(*callee),
                    schedule.callees.of(*callee), seenBy(site, *known), site, standingOf(call));
    } else if (schedule.sameComponent(self, *callee)) {
      // The beta step: closures built for this call alone, applied to a
      // member of the component, keyed by those closures, so their cells
      // are never built.
      if (std::optional<SmallVector<BindingTime>> times = appliesBuiltClosures(call)) {
        const Node *node = nodes.find(*callee);
        const PatternKey *own = nullptr;
        FunctionId owner = *callee;
        if (node)
          idr::match(
              node->key,
              [&](const PatternKey *key) {
                own = key;
                owner = key->owner;
              },
              [](OneOf<const RaiseKey *, const SignatureKey *> auto) {});
        if (std::optional<PatternWant> composed =
                composeKey(nodes.arena(), call, owner, own, *times))
          want = std::optional<Want>(std::move(*composed));
      }
    }
    if (failed(want))
      return failure();
    if (!*want)
      continue;
    FailureOr<std::optional<Nodes::Grant>> granted = nodes.request(self, asking, **want, call);
    if (failed(granted))
      return failure();
    // Refused: the call stays a call.
    if (!*granted)
      continue;
    const Nodes::Grant &grant = **granted;
    FunctionId owner = idr::match(
        grant.asked.key, [](const PatternKey *k) { return k->owner; },
        [](const RaiseKey *k) { return k->callee; }, [](const SignatureKey *k) { return k->owner; });
    FuncOp ownerFn = schedule.readable(self, owner).fn;
    FunctionType type = typeOf(grant, ownerFn, **want, nodes.forms());
    FlatSymbolRefAttr target = grant.asked.name;
    const Node *made = nodes.known(grant.asked.key);
    redirected += idr::match(
        **want,
        [&](const PatternWant &pattern) {
          return support::perform<SpecializeCloneAction>(call, [&] {
            SmallVector<Value> operands =
                operandsOf(rewriter, call, pattern, *grant.key, grant.sources, ownerFn);
            FunctionType passed = passing(call, made, type, operands);
            redirect(rewriter, call, target, passed, call.getIndexArgsAttr(), operands);
          });
        },
        [&](const SignatureWant &copy) {
          return support::perform<SpecializeCloneAction>(call, [&] {
            SmallVector<Value> operands(call.getArgs());
            FunctionType passed = passing(call, made, type, operands);
            redirect(rewriter, call, target, passed,
                     keptArgs(fn.getContext(), call.getIndexArgsAttr(), copy.key->indices), operands);
          });
        },
        [&](const RaiseWant &raise) {
          return support::perform<RaiseAction>(call, [&] {
            Operation *dispatch = raise.consumer.dispatch;
            for (unsigned later = at + 1; later < count; ++later)
              if (!erased.test(later) && dispatch->isAncestor(calls[later]))
                erased.set(later);
            RaiseWant kept = raise;
            FunctionType passed = passing(call, made, type, kept.operands);
            redirect(rewriter, call, target, passed, kept);
          });
        });
  }
  return redirected;
}

struct Redirect : impl::IdrRedirectBase<Redirect> {
  Redirect(optimize::Schedule &schedule, Nodes &nodes, Pass::Statistic &numRedirected,
           InRound place)
      : schedule(schedule), nodes(nodes), numRedirected(numRedirected), place(place) {}

  void runOnOperation() override {
    FailureOr<unsigned> redirected = redirectCalls(getOperation(), schedule, nodes, place);
    if (failed(redirected))
      return signalPassFailure();
    numRedirected += *redirected;
    if (*redirected == 0)
      markAllAnalysesPreserved();
  }

  optimize::Schedule &schedule;
  Nodes &nodes;
  Pass::Statistic &numRedirected;
  InRound place;
};

} // namespace

SmallVector<CallOp> detail::lostTails(FuncOp fn) {
  SmallVector<CallOp> lost;
  for (const tail::Tail &each : tail::tailsOf(fn))
    if (each.repack)
      if (auto call = dyn_cast<CallOp>(each.source))
        lost.push_back(call);
  return lost;
}

std::unique_ptr<Pass> createRedirect(optimize::Schedule &schedule, Nodes &nodes,
                                     Pass::Statistic &redirected, InRound place) {
  return std::make_unique<Redirect>(schedule, nodes, redirected, place);
}

} // namespace idr::specialize
