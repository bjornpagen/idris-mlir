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
// itself: its effects would then interleave with the consumer's, so its
// row carries neither io nor crash, and where it may diverge the consumer
// performs no io. Moving a call is licensed by its row alone.

#include "idr/IR/Effects/Whole.h"
#include "idr/IR/Families/Substitute.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Deduplicate.h"
#include "idr/Transforms/Joins.h"
#include "idr/Transforms/Specialize/Calls.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "mlir/Transforms/RegionUtils.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"

using namespace mlir;

namespace idr::specialize {

//===----------------------------------------------------------------------===//
// Forms
//===----------------------------------------------------------------------===//

// Two consumers are one form exactly when they are one function: equal
// code on equal values, as idr-deduplicate compares. The digest is of the
// structure, read in the same walk upstream's equivalence hashes, so a
// form is never printed.
FormId Forms::intern(OwningOpRef<FuncOp> consumer) {
  llvm::XXH128_hash_t digest = deduplicate::structuralDigest(*consumer);
  std::lock_guard lock(mutex);
  SmallVector<FormId, 1> &bucket = byDigest[digest.low64];
  for (FormId form : bucket)
    if (deduplicate::equivalent(forms[static_cast<unsigned>(form)].fn.get(), *consumer))
      return form;
  auto form = static_cast<FormId>(forms.size());
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
  // The call runs where its consumer is. In the copy, the consumer's
  // effects at one level of the callee's recursion run before the levels
  // around it: a crash of the callee, io of its own, or a loop that does
  // not end after the consumer's io ran, would come after output the
  // program as written never wrote.
  // The call runs where the dispatch, later in its block, stands: no op
  // between them may tell, by the effect system's one question.
  bool runsThere = llvm::all_of(
      llvm::make_range(std::next(call->getIterator()), e->dispatch->getIterator()),
      [&](Operation &between) { return effects::mayMoveAcross(call, &between); });
  effects::Row row = call.getRow();
  if (!runsThere || row.contains(effects::Atom::crash) || row.contains(effects::Atom::io))
    return std::nullopt;
  if (row.contains(effects::Atom::divergence) &&
      effects::rowOf(e->dispatch).contains(effects::Atom::io))
    return std::nullopt;
  // The consumer becomes a function that binds no index variable, and is
  // pushed into the callee's tails, each at its own depth of them: it is
  // the same code at every depth only where it names no index variable and
  // binds none. With none in scope where it stands it names none, every
  // term being scoped where it is written; and no region of its own may
  // bind one, whose levels would be numbered from where it stands.
  if (joins::scopeDepth(call->getParentRegion()) != 0 || bindsLevels(e->dispatch) ||
      llvm::any_of(e->steps(), bindsLevels))
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
  // The consumer keeps the dispatch's own place, so what a raise pushes
  // into a tail is found at the code it came from.
  Location loc = dispatch->getLoc();
  OpBuilder b(ctx);
  FuncOp::Properties properties;
  properties.setSymName(b.getStringAttr("consumer"));
  properties.setFunctionType(TypeAttr::get(FunctionType::get(ctx, inputs, dispatch->getResultTypes())));
  auto fn = FuncOp::create(b, loc, TypeRange(), ValueRange(), properties);
  Block *entry = b.createBlock(&fn.getBody(), {}, inputs, SmallVector<Location>(inputs.size(), loc));
  IRMapping map;
  map.map(call.getResult(0), entry->getArgument(0));
  for (auto [value, arg] : llvm::zip_equal(outside, entry->getArguments().drop_front()))
    map.map(value, arg);
  for (Operation *step : steps)
    b.clone(*step, map);
  Operation *copy = b.clone(*dispatch, map);
  ReturnOp::create(b, loc, copy->getResults());
  return fn;
}

//===----------------------------------------------------------------------===//
// The decision on one call
//===----------------------------------------------------------------------===//

namespace {

// Whether a value of `type` is static data: the hold that is never freed.
bool isStatic(Type type) { return freedBy(type, Release::Static); }

// Whether a parameter of `type` counts what it is given: a reference-
// holding type freed by its count.
bool counts(Type type) { return freedBy(type, Release::Counted); }

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

// The signature copy `call` asks of `callee`: its index arguments' layout
// class where the callee's layout changes under them or a bare tensor
// argument's extent the callee names becomes a constant that `site` lets
// key it, and each parameter that counts made static where the call passes
// static data, which that copy then counts nothing of. None where neither
// changes the callee. The copy's signature is the callee's at those index
// arguments, read through all the callee's extents by the one substitution
// its copy is made by, so each extent whose term is fixed there is static
// in it, and the call casts its operand there.
std::optional<SignatureWant> signatureOf(Arena &arena, CallOp call, FuncOp callee,
                                         FunctionId calleeId, const CallSite &site) {
  ExtentsAttr extents = callee.getExtentsAttr();
  SmallVector<Extent> keying = keyedBy(extents, call.getIndexArgsAttr(), site);
  std::optional<IndexArgsAttr> classes =
      families::classesUnder(callee.getFunctionType(), keying, call.getIndexArgsAttr());
  FunctionType type = callee.getFunctionType();
  SmallVector<Type> inputs(type.getInputs());
  for (auto [input, arg] : llvm::zip_equal(inputs, call.getArgs()))
    if (counts(input) && isStatic(arg.getType()))
      input = atHold(input, Hold::staticData());
  if (!classes && llvm::equal(inputs, type.getInputs()))
    return std::nullopt;
  // Each binder is a level, and a level is a 32-bit number.
  auto binders = static_cast<std::uint32_t>(callee.getBinders().getSorts().size());
  IndexArgsAttr indices = classes ? *classes : families::levelArgs(call.getContext(), 0, binders);
  FunctionType signature = families::substitute(
      FunctionType::get(call.getContext(), inputs, type.getResults()), extents, indices);
  return SignatureWant{arena.key(calleeId, signature, indices)};
}

} // namespace

FailureOr<std::optional<Want>> decide(Arena &arena, Forms &forms, CallOp call,
                                      const Node *requester, FuncOp callee, FunctionId calleeId,
                                      const Node *calleeNode, ArrayRef<BindingTime> seen,
                                      const CallSite &site) {
  // A signature copy first: the layout a call's indices fix and the hold
  // it passes are facts of the call and where it stands, and every later
  // key is composed over the copy's own parameters.
  if (std::optional<SignatureWant> copy = signatureOf(arena, call, callee, calleeId, site))
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
      FormId form = forms.intern(consumerFunction(call, *consumer, free));
      if (admits(form)) {
        RaiseWant want{arena.key(calleeId, form), *consumer, {}};
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
  std::optional<PatternWant> composed = composeKey(arena, call, owner, own, seen);
  if (!composed)
    return std::optional<Want>();
  return std::optional<Want>(std::move(*composed));
}

} // namespace detail
} // namespace idr::specialize
