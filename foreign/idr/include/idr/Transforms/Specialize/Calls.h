// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the specializer reads and rewrites of one call: the shapes its
// arguments have, what it fixes and wants of its callee, the consumer a
// raise takes in, and the call of a node that replaces it. Only the
// specializer's own units read it.
#ifndef IDR_TRANSFORMS_SPECIALIZE_CALLS_H
#define IDR_TRANSFORMS_SPECIALIZE_CALLS_H

#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/SpecializeState.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/STLExtras.h"
#include "llvm/ADT/SmallVector.h"

#include <concepts>
#include <cstdint>
#include <optional>
#include <span>
#include <variant>

namespace idr::specialize {

namespace detail {

// The pattern of `value` and its runtime leaves in pre-order, or a hole
// for a value no pattern knows more of. A constant is itself, a constructor
// its tag over its fields, but a hole where its family gives its cell an
// identity and the call does not take the cell whole; a value entered into
// a quantity-one position is keyed as the value, whose position's type
// keeps its quantity.
const Pattern *shapeOf(Arena &arena, mlir::Value value, llvm::SmallVectorImpl<mlir::Value> &leaves);
// Whether `value` is closed (a constant, or a constructor of closed
// values), and whether every op that built its shape has one use.
bool isClosed(mlir::Value value);
bool usedOnce(mlir::Value value);
// Erases the ops that built the shapes of `values` once nothing uses them.
void eraseUnused(mlir::RewriterBase &rewriter, llvm::ArrayRef<mlir::Value> values);
// The value `pattern` stands for at a position of `type`, each hole taken
// from `holes[next++]`.
mlir::Value rebuild(mlir::OpBuilder &b, mlir::Location loc, const Pattern &pattern, mlir::Type type,
                    llvm::ArrayRef<mlir::Value> holes, unsigned &next);
void holeTypes(const Pattern &pattern, mlir::Type type, llvm::SmallVectorImpl<mlir::Type> &out);

// What a call fixes, by the binding times its callee's parameters have as
// the call sees them: a pattern key over the owner's parameters, or none.
// `own` is the callee's key when the callee is a pattern copy, its holes
// filled with the call's shapes.
std::optional<PatternWant> composeKey(Arena &arena, FunctionCallOpInterface call,
                                      FunctionId owner, const PatternKey *own,
                                      llvm::ArrayRef<BindingTime> seen);

// What a pattern key fixes when it fixes closures alone: the labels of
// those closures, none of them capturing, at any depth, a closure of its
// own label; or data (a constructor of a data family, or a closure that
// would let a recursion walk), which a recursion could walk.
struct FixesData {};
struct FixesClosures {
  llvm::SmallVector<mlir::FlatSymbolRefAttr, 2> labels;
};
using Fixes = std::variant<FixesData, FixesClosures>;
Fixes fixes(const PatternKey &key, mlir::TypeRange params);

// Whether `call` passes a closure, or one a constructor it passes holds,
// that something else uses too.
bool sharesClosure(FunctionCallOpInterface call);
// Where the call applies to a member of its own component closures built
// for it alone: fixed there, varying elsewhere.
std::optional<llvm::SmallVector<BindingTime>> appliesBuiltClosures(FunctionCallOpInterface call);

// Raising.
std::optional<Elimination> consumerOf(FunctionCallOpInterface call);
mlir::OwningOpRef<FuncOp> consumerFunction(FunctionCallOpInterface call,
                                           const Elimination &consumer,
                                           llvm::SmallVectorImpl<mlir::Value> &free);
FuncOp buildRaise(FuncOp callee, const RaiseKey &key, mlir::StringAttr name, const Forms &forms);

// Where a call stands to its callee's call cycle, read once from the
// schedule's components: outside it, or inside it with the closed index
// terms its caller's body holds as its own (Node's `own`; none for a
// function the program held). Inside, a size keys a copy only by those
// terms, so a recursive call that changes a term reaches its copy with
// that axis `?`.
struct OutsideCycle {};
struct InsideCycle {
  llvm::ArrayRef<families::Term> own;
};
using CallSite = std::variant<OutsideCycle, InsideCycle>;

// Where a call in `self`, whose node is `node` (none for a function the
// program held), stands to the call cycle of `callee`: inside it where the
// callee's origin is of one component of the schedule with a cycle whose
// code `self` holds (its own origin's, or for a raise copy a consumer's
// too), and outside it otherwise. The one reading of the program graph's
// components, as waits joined them, for both what a call's arguments vary
// by and what sizes it may key.
CallSite siteOf(const optimize::Schedule &schedule, FunctionId self, const Node *node,
                FunctionId callee);

// Where a call's results go in its caller, read once per caller off its
// tails (tail::tailsOf): to its caller's return through a re-pack, a tail
// lost to a layout, which a copy returning them open makes a tail call; or
// anywhere else, a tail call's free way to the return among them.
enum class TailStanding : std::uint8_t { Elsewhere, LostToLayout };

// The calls of `fn` that are tails lost to a layout: each whose results
// reach `fn`'s return through a re-pack, read off its tails once. Each is
// an ordinary call: a tail call gives its results on freely, and a self
// call modulo a context gives its result into a cell.
llvm::SmallVector<CallOp> lostTails(FuncOp fn);

// The layout a call asks a result of its callee at: as the callee's type
// lays it out, in place where its index is known and its type not marked
// open; or open, as an index unknown at compile time would be, for a tail
// lost to a layout.
enum class ResultLayout : std::uint8_t { AsGiven, AtOpen };

// What `call`, standing where `standing` says, asks of each result: open,
// for a tail lost to a layout, each result its caller lays out otherwise
// than the call gives it, as the layout classes say (the reading by which a
// cast between the two is free or re-packs), so the cast is free and the
// call a tail call; every other result as given. A result no copy of the
// callee could give closed is marked open in the callee's own type, decided
// once when the callee was taken up (openResults), so it reaches the copy
// by the substitution, which keeps the mark, and no call asks for it.
llvm::SmallVector<ResultLayout> layoutsAsked(FunctionCallOpInterface call,
                                             TailStanding standing);

// The results of `callee`'s copy keyed to `layouts` and to the holds
// `passed` names (passedHolds), on the callee's own types, before the key's
// classes: each result asked open at the layout the callee's type marked
// open, at the weakest hold the callee's tails will give it in the copy
// (each tail's value cast to that layout at the grade its reindex gives, a
// value the copy re-packs at no more than a building reindex gives, one a
// call of another function gives at no more than the weakest counted hold,
// as the copy keys that callee open in turn, and the callee's own calls
// tails like any other); then each bounded by the holds passed where a
// lowered parameter may reach it (keyGivenBack, read off `given`). The one
// rule a key's results are made by (SignatureRule).
llvm::SmallVector<mlir::Type> keyedResults(FuncOp callee, llvm::ArrayRef<ResultLayout> layouts,
                                           identities::FactsView given,
                                           llvm::ArrayRef<std::optional<Hold>> passed);

// The one rule a signature key is made by, for `call` of `callee`, read once
// each time the call is decided: the class of its index arguments where the
// callee's layout changes under them or a bare tensor argument's extent the
// callee names becomes a constant that the call's site lets key it, and
// what it asks of each result where it stands (layoutsAsked). Its key
// judges nothing of the call's caller: the redirect asks whether the caller
// reads what the copy gives (signatureOf), and a caller decided between
// waves reads it (openResults), both off the table (Nodes::signatureOf,
// Nodes::read).
struct SignatureRule {
  FunctionCallOpInterface call;
  FuncOp callee;
  FunctionId calleeId;
  identities::FactsView given;
  std::optional<IndexArgsAttr> classes;
  llvm::SmallVector<ResultLayout> layouts;

  // The key at the holds `passed` names (passedHolds; none where a
  // parameter keeps its own), interned in `arena`: each parameter at its
  // hold, each result as keyedResults gives it, the callee's signature at
  // the classes; null where nothing changes the callee.
  const SignatureKey *keyAt(Arena &arena, llvm::ArrayRef<std::optional<Hold>> passed) const;
};
SignatureRule signatureRule(FunctionCallOpInterface call, FuncOp callee, FunctionId calleeId,
                            identities::FactsView given, const CallSite &site,
                            TailStanding standing);

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
// caller past its decided return, so such a key is not granted; nor in
// idr-specialize's round, which decides no caller again.
bool readsAsKeyed(FunctionCallOpInterface call, llvm::ArrayRef<ResultLayout> layouts,
                  mlir::TypeRange results);

// What holds the signature a key's copy gives, read where a call is judged:
// idr-optimize's table (Nodes::signatureOf: the copy's node's, which the
// decisions of its component may restate, or the key's), or idr-specialize's
// round, whose copies give what their keys say.
template <class T>
concept KeySignatures = requires(const T &table, const SignatureKey *key) {
  { table.signatureOf(key) } -> std::same_as<mlir::FunctionType>;
};

// The signature copy `call` asks of `callee` (SignatureRule), where its
// caller reads what the copy `table` holds for the key gives (at which the
// call is made); none where nothing changes the callee, or where the caller
// would read a result at more than the copy gives (readsAsKeyed). The key
// states what it can. Where the holds passed lower a result the caller
// reads at more, each hold that fits its parameter's (static data where the
// callee counts nothing, a claim the parameter forgets) is left out of the
// key, the argument crossing at the parameter's hold until it is shared
// down (shareCrossings), and the key keeps the rest: its classes, a result
// asked open, which a tail lost to a layout needs to be a tail, and each
// hold its argument cannot cross at, a claim weaker than its parameter's.
// Its keys are interned in `arena`.
template <KeySignatures T>
std::optional<SignatureWant> signatureOf(Arena &arena, const T &table,
                                         FunctionCallOpInterface call, FuncOp callee,
                                         FunctionId calleeId, identities::FactsView given,
                                         const CallSite &site, TailStanding standing) {
  SignatureRule rule = signatureRule(call, callee, calleeId, given, site, standing);
  // The key at the holds `passed` names, where something changes the
  // callee and the caller reads what its copy gives.
  auto keyedAt = [&](llvm::ArrayRef<std::optional<Hold>> passed) -> std::optional<SignatureWant> {
    const SignatureKey *key = rule.keyAt(arena, passed);
    if (!key || !readsAsKeyed(call, rule.layouts, table.signatureOf(key).getResults()))
      return std::nullopt;
    return SignatureWant{key};
  };
  llvm::ArrayRef<mlir::Type> inputs = callee.getArgumentTypes();
  llvm::SmallVector<std::optional<Hold>> passed = passedHolds(call, inputs);
  if (std::optional<SignatureWant> keyed = keyedAt(passed))
    return keyed;
  llvm::SmallVector<std::optional<Hold>> crossing(passed);
  for (auto [hold, input] : llvm::zip_equal(crossing, inputs))
    if (std::optional<Hold> own = holdOf(input); hold && own && hold->fits(*own))
      hold = std::nullopt;
  if (llvm::equal(crossing, passed))
    return std::nullopt;
  return keyedAt(crossing);
}

// What a call wants, by kind: its signature copy where its index arguments
// fix a layout class the callee's layout changes under or a bare tensor
// argument's extent the callee names, as `site` lets a size key it, or it
// passes an argument at a hold its parameter does not have (each result
// that argument may reach, by the callee's published facts `given`, keyed
// with it), or `standing` is a tail lost to a layout, judged against what
// the copy `nodes` holds for its key gives (Nodes::signatureOf); else its
// raise; else its pattern key. Keys and forms are interned in `nodes`'
// arena and table of forms.
mlir::FailureOr<std::optional<Want>> decide(Nodes &nodes, FunctionCallOpInterface call,
                                            const Node *requester, FuncOp callee,
                                            FunctionId calleeId,
                                            const Node *calleeNode, identities::FactsView given,
                                            llvm::ArrayRef<BindingTime> seen,
                                            const CallSite &site, TailStanding standing);

// The index arguments a call of a signature copy passes: the call's own
// `call` at each binder the copy keeps, where the key's term in `classes` is
// the level the binder becomes in the copy, as the one substitution the copy
// is made by reads it; none where a class is fixed, the key's term closed.
IndexArgsAttr keptArgs(mlir::MLIRContext *ctx, IndexArgsAttr call, IndexArgsAttr classes);

// Calling a node. A redirect erases `call` and gives the call of the copy
// that stands in its place, the member of the call family its place makes.
llvm::SmallVector<mlir::Value> operandsOf(mlir::RewriterBase &rewriter,
                                          FunctionCallOpInterface call, const PatternWant &want,
                                          const PatternKey &key, llvm::ArrayRef<Source> sources,
                                          FuncOp owner);
FunctionCallOpInterface redirect(mlir::RewriterBase &rewriter, FunctionCallOpInterface call,
                                 mlir::FlatSymbolRefAttr target, mlir::FunctionType type,
                                 IndexArgsAttr indices, llvm::ArrayRef<mlir::Value> operands);
FunctionCallOpInterface redirect(mlir::RewriterBase &rewriter, FunctionCallOpInterface call,
                                 mlir::FlatSymbolRefAttr target, mlir::FunctionType type,
                                 const RaiseWant &want);

} // namespace detail
} // namespace idr::specialize

#endif // IDR_TRANSFORMS_SPECIALIZE_CALLS_H
