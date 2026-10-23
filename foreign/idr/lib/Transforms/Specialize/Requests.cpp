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
#include "idr/Transforms/Optimize.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/BitVector.h"
#include "llvm/ADT/STLExtras.h"

#define GEN_PASS_DEF_IDRREDIRECT
#include "idr/IR/Generated/PassDialects.h.inc"

namespace idr {
#include "idr/Transforms/InnerPasses.h.inc"
} // namespace idr

using namespace mlir;

namespace idr::specialize {

using namespace detail;

namespace {

// Where a call in `self`, whose node is `node` (none for a function the
// program held), stands to the call cycle of `callee`: inside it where the
// callee's origin is of one component of the schedule with a cycle whose
// code `self` holds (its own origin's, or for a raise copy a consumer's
// too), and outside it otherwise. The one reading of the program graph's
// components, as waits joined them, for both what a call's arguments vary
// by and what sizes it may key.
CallSite siteOf(const optimize::Schedule &schedule, FunctionId self, const Node *node,
                FunctionId callee) {
  FunctionId theirs = schedule.originOf(callee);
  auto inside = [&](FunctionId cycle) { return schedule.sameComponent(cycle, theirs); };
  if (!node)
    return inside(schedule.originOf(self)) ? CallSite(InsideCycle{}) : CallSite(OutsideCycle{});
  if (llvm::any_of(node->cycles, inside))
    return InsideCycle{node->own};
  return OutsideCycle{};
}

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

// The index arguments a call of a signature copy passes: the call's own at
// each binder the copy keeps, where the copy's classes name a variable,
// none where a class is fixed.
IndexArgsAttr keptArgs(MLIRContext *ctx, IndexArgsAttr call, IndexArgsAttr classes) {
  if (!call)
    return call;
  SmallVector<families::TermNode> kept;
  std::uint64_t count = 0;
  ArrayRef<families::TermNode> mine = call.getTerms(), theirs = classes.getTerms();
  while (!mine.empty()) {
    families::Term own(mine), fixed(theirs);
    if (fixed.head().kind == TermKind::Level) {
      llvm::append_range(kept, own.nodes());
      ++count;
    }
    mine = mine.drop_front(own.nodes().size());
    theirs = theirs.drop_front(fixed.nodes().size());
  }
  return IndexArgsAttr::get(ctx, kept, count);
}

// Each call of `fn` in walk order: its want decided, its key requested,
// and the call made a call of the granted copy. How many calls it
// redirected; a failure is an internal error, emitted.
//
// The calls are numbered by their place in the one walk. A raise erases
// the dispatch it moves into the copy, later in the call's block, and
// every call inside it, which the walk has not met yet; no other redirect
// erases a call but its own. So before a raise, each call still to come
// that the dispatch holds is marked by its number, and the walk passes it.
FailureOr<unsigned> redirectCalls(FuncOp fn, optimize::Schedule &schedule, Nodes &nodes) {
  FunctionId self = schedule.graph.id(FlatSymbolRefAttr::get(fn.getSymNameAttr()));
  Requester &asking = schedule.requesterOf(self);
  const Node *requester = nodes.find(self);
  SmallVector<CallOp> calls;
  fn.walk<WalkOrder::PreOrder>([&](CallOp call) { calls.push_back(call); });
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
      want = decide(nodes.arena(), nodes.forms(), call, requester, known->fn, *callee,
                    nodes.find(*callee), seenBy(site, *known), site);
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
    redirected += idr::match(
        **want,
        [&](const PatternWant &pattern) {
          return support::perform<SpecializeCloneAction>(call, [&] {
            SmallVector<Value> operands =
                operandsOf(rewriter, call, pattern, *grant.key, grant.sources, ownerFn);
            redirect(rewriter, call, target, type, call.getIndexArgsAttr(), operands);
          });
        },
        [&](const SignatureWant &copy) {
          return support::perform<SpecializeCloneAction>(call, [&] {
            SmallVector<Value> operands(call.getArgs());
            redirect(rewriter, call, target, type,
                     keptArgs(fn.getContext(), call.getIndexArgsAttr(), copy.key->indices), operands);
          });
        },
        [&](const RaiseWant &raise) {
          return support::perform<RaiseAction>(call, [&] {
            Operation *dispatch = raise.consumer.dispatch;
            for (unsigned later = at + 1; later < count; ++later)
              if (!erased.test(later) && dispatch->isAncestor(calls[later]))
                erased.set(later);
            redirect(rewriter, call, target, type, raise);
          });
        });
  }
  return redirected;
}

struct Redirect : impl::IdrRedirectBase<Redirect> {
  Redirect(optimize::Schedule &schedule, Nodes &nodes, Pass::Statistic &numRedirected)
      : schedule(schedule), nodes(nodes), numRedirected(numRedirected) {}

  void runOnOperation() override {
    FailureOr<unsigned> redirected = redirectCalls(getOperation(), schedule, nodes);
    if (failed(redirected))
      return signalPassFailure();
    numRedirected += *redirected;
    if (*redirected == 0)
      markAllAnalysesPreserved();
  }

  optimize::Schedule &schedule;
  Nodes &nodes;
  Pass::Statistic &numRedirected;
};

} // namespace

std::unique_ptr<Pass> createRedirect(optimize::Schedule &schedule, Nodes &nodes,
                                     Pass::Statistic &redirected) {
  return std::make_unique<Redirect>(schedule, nodes, redirected);
}

} // namespace idr::specialize
