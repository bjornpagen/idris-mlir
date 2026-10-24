// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// When a call may be raised, the consumer a raise copy takes in as code,
// the run's table of consumer forms, and the one decision on a call that
// the redirect step reads.
//
// Raising moves the consumer of a call's result into the callee's tails:
// the dispatch that is all its one use does with it (the match an apply
// became, or the output of a string). Nothing may run between the call and
// the dispatch that could tell: the dispatch and its steps are in the
// call's block, and the call may run at the dispatch. Nor may the callee
// itself: in the copy the consumer runs at the callee's tails, before what
// the callee still does around them, so the consumer trades places with
// the call as the call does with each op it moves across, by the effect
// system's one question. Moving a call is licensed by its row alone. The
// consumer is a function, so it returns an array `?` at every axis, each
// size the dispatch's type fixed kept in its extents and its value cast
// before the return; a dispatch that gives a graded array with a static
// axis, which no cast reaches, is not raised.

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Deduplicate.h"
#include "idr/Transforms/Joins.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/Dialect/Tensor/IR/Tensor.h"
#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/IR/OperationSupport.h"
#include "mlir/Transforms/RegionUtils.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

#include <variant>

using namespace mlir;

namespace idr::specialize {

//===----------------------------------------------------------------------===//
// Forms
//===----------------------------------------------------------------------===//

namespace {

// A consumer's bucket among the forms this process met: each op it holds,
// its own first, hashed as upstream's equivalence hashes one, by its name
// and the uniqued identities of its attributes, properties and result
// types; where its operands come from is the comparison's to tell. Nothing
// inside an attribute or a type is walked and nothing is made. Two
// consumers that are one function hash alike: every consumer is named
// alike, so the name a function's facts leave out tells none apart.
llvm::hash_code bucketOf(FuncOp consumer) {
  llvm::hash_code hash{};
  consumer->walk<WalkOrder::PreOrder>([&](Operation *op) {
    hash = llvm::hash_combine(
        hash, OperationEquivalence::computeHash(op, OperationEquivalence::ignoreHashValue,
                                                OperationEquivalence::ignoreHashValue,
                                                OperationEquivalence::IgnoreLocations));
  });
  return hash;
}

} // namespace

// Two consumers are one form exactly when they are one function: equal
// code on equal values, as idr-deduplicate compares, within one bucket.
// The digest of its structure, the same in every process, is what names
// the raise copies of a form, so it is read once, of a form not met
// before; a consumer met again costs one walk of its ops and a comparison
// with each form in its bucket.
FormId Forms::intern(OwningOpRef<FuncOp> consumer) {
  llvm::hash_code hash = bucketOf(*consumer);
  std::lock_guard lock(mutex);
  SmallVector<FormId, 1> &bucket = byBucket[hash];
  for (FormId form : bucket)
    if (deduplicate::equivalent(forms[static_cast<unsigned>(form)].fn.get(), *consumer))
      return form;
  auto form = static_cast<FormId>(forms.size());
  llvm::XXH128_hash_t digest = deduplicate::structuralDigest(*consumer);
  forms.push_back({std::move(consumer), digest});
  bucket.push_back(form);
  return form;
}

FuncOp Forms::at(FormId form) const {
  std::lock_guard lock(mutex);
  return forms[static_cast<unsigned>(form)].fn.get();
}

llvm::XXH128_hash_t Forms::digestOf(FormId form) const {
  std::lock_guard lock(mutex);
  return forms[static_cast<unsigned>(form)].digest;
}

namespace detail {

//===----------------------------------------------------------------------===//
// The consumer
//===----------------------------------------------------------------------===//

namespace {

// Whether `root` or an op inside it has a region that binds index
// variables, which each binder says through the interface.
bool bindsLevels(Operation *root) {
  return root
      ->walk([](ErasedBinderOpInterface binder) {
        for (Region &region : binder->getRegions())
          if (!binder.getBoundSorts(region).empty())
            return WalkResult::interrupt();
        return WalkResult::advance();
      })
      .wasInterrupted();
}

} // namespace

std::optional<Elimination> consumerOf(CallOp call) {
  if (call->getNumResults() != 1 || !call->getResult(0).hasOneUse())
    return std::nullopt;
  std::optional<Elimination> e = eliminationAt(*call->getResult(0).getUses().begin());
  if (!e || e->dispatch->getBlock() != call->getBlock())
    return std::nullopt;
  // The call runs where the dispatch, later in its block, stands, and the
  // consumer runs inside the callee: in the copy, the consumer's effects at
  // one level of the callee's recursion run before what the levels around
  // it still do. So no op between the call and the dispatch may tell the
  // call moved, and no op of the consumer may tell it ran before the
  // callee's own effects, each by the effect system's one question.
  bool runsThere = llvm::all_of(
      llvm::make_range(std::next(call->getIterator()), e->dispatch->getIterator()),
      [&](Operation &between) { return effects::mayMoveAcross(call, &between); });
  SmallVector<Operation *> steps = e->steps();
  auto beforeCallee = [&](Operation *consumed) { return effects::mayMoveAcross(consumed, call); };
  if (!runsThere || !beforeCallee(e->dispatch) || !llvm::all_of(steps, beforeCallee))
    return std::nullopt;
  // The consumer becomes a function that binds no index variable, and is
  // pushed into the callee's tails, each at its own depth of them: it is
  // the same code at every depth only where it names no index variable and
  // binds none. With none in scope where it stands it names none, every
  // term being scoped where it is written; and no region of its own may
  // bind one, whose levels would be numbered from where it stands.
  if (joins::scopeDepth(call->getParentRegion()) != 0 || bindsLevels(e->dispatch) ||
      llvm::any_of(steps, bindsLevels))
    return std::nullopt;
  // The consumer returns what the dispatch gives, and no function returns
  // a graded array with a static axis: the call stays a call, the program
  // less optimized and nothing refused.
  if (!llvm::all_of(e->dispatch->getResultTypes(), returnable))
    return std::nullopt;
  return e;
}

OwningOpRef<FuncOp> consumerFunction(CallOp call, const Elimination &consumer,
                                     SmallVectorImpl<Value> &free) {
  MLIRContext *ctx = call.getContext();
  // The steps from the call's result to the dispatch, each the one use of
  // the one before, in the order they run.
  SmallVector<Operation *> steps = consumer.steps();
  Operation *dispatch = consumer.dispatch;

  // The values the dispatch and its regions read from outside it, its own
  // operands first, but the one the steps hand it, which the copy makes
  // itself: the call's result and each step's are the one use of what
  // made them, so no other op of the dispatch reads one.
  Value handed = steps.empty() ? call.getResult(0) : steps.back()->getResult(0);
  llvm::SetVector<Value> outside;
  for (Value operand : dispatch->getOperands())
    if (operand != handed)
      outside.insert(operand);
  getUsedValuesDefinedAbove(dispatch->getRegions(), outside);
  llvm::append_range(free, outside);

  SmallVector<Type> inputs{call.getResult(0).getType()};
  llvm::append_range(inputs, ValueRange(outside.getArrayRef()).getTypes());
  // It returns what the dispatch gives as a function returns it, `?` at
  // every axis of an array, each size the dispatch's type fixed kept as
  // its extents' constant; a raise copy returns what it returns.
  SmallVector<ExtentAttr> entries;
  SmallVector<Type> results;
  for (auto [position, type] : llvm::enumerate(dispatch->getResultTypes()))
    results.push_back(returnedAs(type, static_cast<std::uint32_t>(position), entries));
  // The consumer keeps the dispatch's own place, so what a raise pushes
  // into a tail is found at the code it came from.
  Location loc = dispatch->getLoc();
  OpBuilder b(ctx);
  FuncOp::Properties properties;
  properties.setSymName(b.getStringAttr("consumer"));
  properties.setFunctionType(TypeAttr::get(FunctionType::get(ctx, inputs, results)));
  if (!entries.empty())
    properties.setExtents(ExtentsAttr::get(ctx, ArrayRef<ExtentAttr>(entries)));
  auto fn = FuncOp::create(b, loc, TypeRange(), ValueRange(), properties);
  Block *entry = b.createBlock(&fn.getBody(), {}, inputs, SmallVector<Location>(inputs.size(), loc));
  IRMapping map;
  map.map(call.getResult(0), entry->getArgument(0));
  for (auto [value, arg] : llvm::zip_equal(outside, entry->getArguments().drop_front()))
    map.map(value, arg);
  for (Operation *step : steps)
    b.clone(*step, map);
  Operation *copy = b.clone(*dispatch, map);
  // A value whose type fixed a size is cast to the type returned before the
  // return, so a raise pushes the cast into each tail with the consumer.
  SmallVector<Value> returned;
  for (auto [value, type] : llvm::zip_equal(copy->getResults(), results)) {
    if (value.getType() == type)
      returned.push_back(value);
    else
      returned.push_back(tensor::CastOp::create(b, loc, type, value).getResult());
  }
  ReturnOp::create(b, loc, returned);
  return fn;
}

//===----------------------------------------------------------------------===//
// The decision on one call
//===----------------------------------------------------------------------===//

namespace {

// The callee's extents whose sizes may key a copy at `site`, in order. From
// outside the callee's call cycle, every one. From inside it, each whose
// index variables the call gives no closed term but one its caller's body
// holds as its own: a recursive call that changes a term (`go (S n)`, which
// the copy at 0 calls at 1) reaches its copy with that axis `?`, as an axis
// the callee names no extent for. So every size a cycle's copies are keyed
// at entered the cycle by one of the finitely many calls into it, and
// specialization on sizes ends with no budget. A term over the caller's own
// binders is no size, and keys nothing wherever it stands. A layout class
// keys a copy whatever the site, the shape budget bounding its alphabet;
// where one keeps an index variable for a data type, the axes that variable
// names are static with it. Each entry is a view of the callee's uniqued
// attribute, so nothing is made here, on a worker.
SmallVector<Extent> keyedBy(ExtentsAttr extents, IndexArgsAttr args, const CallSite &site) {
  SmallVector<Extent> keying;
  if (!extents)
    return keying;
  ArrayRef<ExtentAttr> entries = extents.getEntries();
  idr::match(
      site,
      [&](OutsideCycle) {
        for (ExtentAttr attr : entries)
          keying.push_back(attr.extent());
      },
      [&](const InsideCycle &inside) {
        // An entry names a binder of the callee, so a callee with one binds
        // one, and the call gives each a term.
        if (entries.empty())
          return;
        SmallVector<families::Term> terms = families::termsOf(args.getTerms(), args.getCount());
        auto callersOwn = [&](const families::TermNode &node) {
          if (node.kind != TermKind::Level)
            return true;
          assert(node.value < terms.size() && "an extent's term names a binder of its function");
          families::Term term = terms[node.value];
          return !term.isClosed() || llvm::is_contained(inside.own, term);
        };
        for (ExtentAttr attr : entries) {
          Extent entry = attr.extent();
          if (llvm::all_of(entry.term.nodes(), callersOwn))
            keying.push_back(entry);
        }
      });
  return keying;
}

} // namespace

SmallVector<ResultLayout> layoutsAsked(CallOp call, TailStanding standing) {
  SmallVector<ResultLayout> asked(call->getNumResults(), ResultLayout::AsGiven);
  if (standing == TailStanding::Elsewhere)
    return asked;
  // A tail's results are its caller's, one for one: the way from the call
  // to the return forwards each in its place.
  auto caller = call->getParentOfType<FuncOp>();
  for (auto [ask, given, returned] :
       llvm::zip_equal(asked, call.getResultTypes(), caller.getResultTypes()))
    if (families::layoutMatch(given, returned) == LayoutMatch::OtherLayout)
      ask = ResultLayout::AtOpen;
  return asked;
}

// The rule a signature key is made by: the classes of the call's index
// arguments where the callee's layout changes under them or a bare tensor
// argument's extent the callee names becomes a constant that `site` lets
// key it, and each result its caller needs open, where `standing` is a tail
// lost to a layout.
SignatureRule signatureRule(CallOp call, FuncOp callee, FunctionId calleeId,
                            identities::FactsView given, const CallSite &site,
                            TailStanding standing) {
  SmallVector<Extent> keying = keyedBy(callee.getExtentsAttr(), call.getIndexArgsAttr(), site);
  return SignatureRule{
      call,
      callee,
      calleeId,
      given,
      families::classesUnder(callee.getFunctionType(), keying, call.getIndexArgsAttr()),
      layoutsAsked(call, standing)};
}

// Each parameter at the hold the call passes where the two differ (static
// data where the callee would count, which that copy then counts nothing
// of; a claim re-grading lowered, which no cast raises back), and its
// results as keyedResults gives them. The copy's signature is the callee's
// at the classes, every binder they do not fix kept as the copy's own
// level, read through all the callee's extents by the one substitution its
// copy is made by, so each extent whose term is fixed there is static in
// it, and the call casts its operand there; a result the callee's type
// marks open stays open, and a result asked open, marked open on the
// callee's type, keeps the mark through the substitution, which the copy's
// tails give. The rule is read through a const reference, so its ops'
// handles are copied out, as an op is passed.
const SignatureKey *SignatureRule::keyAt(Arena &arena,
                                         ArrayRef<std::optional<Hold>> passed) const {
  FuncOp fn = callee;
  MLIRContext *ctx = fn.getContext();
  FunctionType type = fn.getFunctionType();
  SmallVector<Type> inputs(type.getInputs());
  for (auto [input, hold] : llvm::zip_equal(inputs, passed))
    if (hold)
      input = atHold(input, *hold);
  if (!classes && llvm::equal(inputs, type.getInputs()) &&
      !llvm::is_contained(layouts, ResultLayout::AtOpen))
    return nullptr;
  SmallVector<Type> returned = keyedResults(fn, layouts, given, passed);
  // Each binder is a level, and a level is a 32-bit number. With no class
  // fixed, every binder stays, each the copy's level it was the callee's.
  auto binders = static_cast<std::uint32_t>(fn.getBinders().getSorts().size());
  IndexArgsAttr indices = classes ? *classes : families::levelArgs(ctx, 0, binders);
  // The classes keep every index the call's view closes, results included,
  // so the copy's own result is that view, closed, and its tails cast it to
  // the open type: what a known index lets it build in place, it builds.
  FunctionType signature = families::substitute(FunctionType::get(ctx, inputs, returned),
                                                fn.getExtentsAttr(), indices);
  return arena.key(calleeId, signature, indices);
}

namespace {

// Whether `call`'s caller reads each result of a copy giving `results` (as
// the table holds it: its key's, substituted, or those the decisions of the
// component the copy joined restated) at no more than the copy gives it.
// The caller took each result when it was decided, between waves
// (openResults), off the same table, and was decided again at each
// restatement since (Nodes::restate): one asked as given at the hold the
// call's own result has, which that copy then gives (a result laid out at
// the call so as to hold no reference has none to read); one asked open at
// its own result's hold, to which the re-pack after the call gives it,
// which the copy's then fits. A key made later gives less only where a
// parameter its operand lowered in the caller's own round may reach a
// result (static data placed at the argument), which would re-grade the
// caller past its decided return, so such a key is not granted.
bool readsAsKeyed(CallOp call, ArrayRef<ResultLayout> layouts, TypeRange results) {
  auto caller = call->getParentOfType<FuncOp>();
  for (auto [index, layout] : llvm::enumerate(layouts)) {
    auto position = static_cast<unsigned>(index);
    std::optional<Hold> gives = holdOf(results[position]);
    if (!gives)
      continue;
    if (layout == ResultLayout::AsGiven) {
      if (std::optional<Hold> took = holdOf(call.getResultTypes()[position]);
          took && *took != *gives)
        return false;
      continue;
    }
    std::optional<Hold> held = holdOf(caller.getResultTypes()[position]);
    if (held && !gives->fits(*held))
      return false;
  }
  return true;
}

// The signature copy `call` asks of `callee` (SignatureRule), where its
// caller reads what the copy the table holds for the key gives
// (Nodes::signatureOf: its key's results, or those the decisions of its
// component restated, at which the call is made); none where nothing
// changes the callee, or where the caller would read a result at more than
// the copy gives (readsAsKeyed).
// The key states what it can. Where the holds passed lower a result the
// caller reads at more, each hold that fits its parameter's (static data
// where the callee counts nothing, a claim the parameter forgets) is left
// out of the key, the argument crossing at the parameter's hold until its
// function is final (shareCrossings), and the key keeps the rest: its
// classes, a result asked open, which a tail lost to a layout needs to be
// a tail, and each hold its argument cannot cross at, a claim weaker than
// its parameter's.
std::optional<SignatureWant> signatureOf(Nodes &nodes, CallOp call, FuncOp callee,
                                         FunctionId calleeId, identities::FactsView given,
                                         const CallSite &site, TailStanding standing) {
  SignatureRule rule = signatureRule(call, callee, calleeId, given, site, standing);
  // The key at the holds `passed` names, where something changes the
  // callee and the caller reads what its copy gives.
  auto keyedAt = [&](ArrayRef<std::optional<Hold>> passed) -> std::optional<SignatureWant> {
    const SignatureKey *key = rule.keyAt(nodes.arena(), passed);
    if (!key || !readsAsKeyed(call, rule.layouts, nodes.signatureOf(key).getResults()))
      return std::nullopt;
    return SignatureWant{key};
  };
  ArrayRef<Type> inputs = callee.getArgumentTypes();
  SmallVector<std::optional<Hold>> passed = passedHolds(call, inputs);
  if (std::optional<SignatureWant> keyed = keyedAt(passed))
    return keyed;
  SmallVector<std::optional<Hold>> crossing(passed);
  for (auto [hold, input] : llvm::zip_equal(crossing, inputs))
    if (std::optional<Hold> own = holdOf(input); hold && own && hold->fits(*own))
      hold = std::nullopt;
  if (llvm::equal(crossing, passed))
    return std::nullopt;
  return keyedAt(crossing);
}

} // namespace

FailureOr<std::optional<Want>> decide(Nodes &nodes, CallOp call, const Node *requester,
                                      FuncOp callee, FunctionId calleeId,
                                      const Node *calleeNode, identities::FactsView given,
                                      ArrayRef<BindingTime> seen, const CallSite &site,
                                      TailStanding standing) {
  // A signature copy first: the layout a call's indices fix, the hold it
  // passes and the layout its caller returns a tail at are facts of the
  // call and where it stands, and every later key is composed over the
  // copy's own parameters.
  if (std::optional<SignatureWant> copy =
          signatureOf(nodes, call, callee, calleeId, given, site, standing))
    return std::optional<Want>(*copy);

  // A pattern copy raises nothing; a raise copy only with its own
  // consumer, where its callee's tails meet it again; any other function
  // freely. The callee returns from its one block, where the consumer is
  // pushed; one that never returns has no tail to push it to.
  // What the requester may raise: anything, nothing, or only its own form.
  struct Free {};
  struct None {};
  struct Only {
    FormId form;
  };
  std::variant<Free, None, Only> raises = Free{};
  if (requester)
    raises = idr::match(
        requester->key,
        [](const PatternKey *) -> std::variant<Free, None, Only> { return None{}; },
        [](const RaiseKey *raise) -> std::variant<Free, None, Only> { return Only{raise->form}; },
        [](const SignatureKey *) -> std::variant<Free, None, Only> { return Free{}; });
  auto admits = [&](FormId form) {
    return idr::match(
        raises, [](Free) { return true; }, [](None) { return false; },
        [&](Only only) { return only.form == form; });
  };
  bool mayRaise =
      idr::match(raises, [](None) { return false; }, [](OneOf<Free, Only> auto) { return true; });
  if (mayRaise && callee.getBody().front().getTerminator()->hasTrait<OpTrait::ReturnLike>())
    if (std::optional<Elimination> consumer = consumerOf(call)) {
      SmallVector<Value> free;
      FormId form = nodes.forms().intern(consumerFunction(call, *consumer, free));
      if (admits(form)) {
        RaiseWant want{nodes.arena().key(calleeId, form), *consumer, {}};
        llvm::append_range(want.operands, call.getArgs());
        llvm::append_range(want.operands, free);
        return std::optional<Want>(std::move(want));
      }
    }

  // A call of a pattern copy is keyed over the copy's owner's parameters.
  const PatternKey *own = nullptr;
  FunctionId owner = calleeId;
  if (calleeNode)
    idr::match(
        calleeNode->key,
        [&](const PatternKey *key) {
          own = key;
          owner = key->owner;
        },
        [](OneOf<const RaiseKey *, const SignatureKey *> auto) {});
  std::optional<PatternWant> composed = composeKey(nodes.arena(), call, owner, own, seen);
  if (!composed)
    return std::optional<Want>();
  return std::optional<Want>(std::move(*composed));
}

} // namespace detail
} // namespace idr::specialize
