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

#include "idr/IR/Effects/Query.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/Deduplicate.h"
#include "Calls.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/IRMapping.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SetVector.h"
#include "llvm/ADT/SmallPtrSet.h"

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
  return e;
}

OwningOpRef<FuncOp> consumerFunction(CallOp call, const Elimination &consumer,
                                     SmallVectorImpl<Value> &free) {
  MLIRContext *ctx = call.getContext();
  // The steps from the call's result to the dispatch, each the one use of
  // the one before, in the order they run.
  SmallVector<Operation *> steps = consumer.steps();
  Operation *dispatch = consumer.dispatch;

  // The values the dispatch and its regions read from outside it, in the
  // order a pre-order walk first reads them, but the call's result and
  // what the steps make, which the copy makes itself.
  llvm::SmallPtrSet<Operation *, 4> made(steps.begin(), steps.end());
  made.insert(call);
  llvm::SetVector<Value> outside;
  dispatch->walk<WalkOrder::PreOrder>([&](Operation *op) {
    for (Value operand : op->getOperands()) {
      if (Operation *def = operand.getDefiningOp(); def && made.contains(def))
        continue;
      Region *region = operand.getParentRegion();
      if (!region || !dispatch->isAncestor(region->getParentOp()))
        outside.insert(operand);
    }
  });
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

// The signature copy `call` asks of `callee`: its index arguments' layout
// class where the callee's layout changes under them, and each parameter
// that counts made static where the call passes static data, which that
// copy then counts nothing of. None where neither changes the callee.
std::optional<SignatureWant> signatureOf(Arena &arena, CallOp call, FuncOp callee,
                                         FunctionId calleeId) {
  std::optional<IndexArgsAttr> classes =
      families::classesUnder(callee.getFunctionType(), call.getIndexArgsAttr());
  FunctionType type = callee.getFunctionType();
  SmallVector<Type> inputs(type.getInputs());
  for (auto [input, arg] : llvm::zip_equal(inputs, call.getArgs()))
    if (counts(input) && isStatic(arg.getType()))
      input = atHold(input, Hold::staticData());
  if (!classes && llvm::equal(inputs, type.getInputs()))
    return std::nullopt;
  unsigned binders = callee.getBindersAttr() ? callee.getBindersAttr().getSorts().size() : 0;
  IndexArgsAttr indices = classes ? *classes : families::levelArgs(call.getContext(), 0, binders);
  FunctionType signature = families::substitute(
      FunctionType::get(call.getContext(), inputs, type.getResults()), indices);
  return SignatureWant{arena.key(calleeId, signature, indices)};
}

} // namespace

FailureOr<std::optional<Want>> decide(Arena &arena, Forms &forms, CallOp call,
                                      const Node *requester, FuncOp callee, FunctionId calleeId,
                                      const Node *calleeNode, ArrayRef<BindingTime> seen) {
  // A signature copy first: the layout a call's indices fix and the hold
  // it passes are facts of the call alone, and every later key is composed
  // over the copy's own parameters.
  if (std::optional<SignatureWant> copy = signatureOf(arena, call, callee, calleeId))
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
  bool mayRaise = idr::match(raises, [](None) { return false; }, [](const auto &) { return true; });
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
        [](const auto *) {});
  std::optional<PatternWant> composed = composeKey(arena, call, owner, own, seen);
  if (!composed)
    return std::optional<Want>();
  return std::optional<Want>(std::move(*composed));
}

} // namespace detail
} // namespace idr::specialize
