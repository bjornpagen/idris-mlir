// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// What the specializer reads and rewrites of one call: the shapes its
// arguments have, what it fixes and wants of its callee, the consumer a
// raise takes in, and the call of a node that replaces it. Only the
// specializer's own units read it.
#ifndef IDR_TRANSFORMS_SPECIALIZE_CALLS_H
#define IDR_TRANSFORMS_SPECIALIZE_CALLS_H

#include "idr/IR/IdrDialect.h"
#include "idr/IR/Symbols.h"
#include "idr/Transforms/SpecializeState.h"

#include "mlir/IR/Builders.h"
#include "mlir/IR/OwningOpRef.h"
#include "mlir/IR/PatternMatch.h"
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/SmallVector.h"

#include <cstdint>
#include <optional>
#include <span>
#include <variant>

namespace idr::specialize {

namespace detail {

// The pattern of `value` and its runtime leaves in pre-order, or a hole
// for a value no pattern knows more of. A constant is itself, a constructor
// its tag over its fields; a value entered into a quantity-one position is
// keyed as the value, whose position's type keeps its quantity.
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
std::optional<PatternWant> composeKey(Arena &arena, CallOp call, FunctionId owner,
                                      const PatternKey *own, llvm::ArrayRef<BindingTime> seen);

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
bool sharesClosure(CallOp call);
// Where the call applies to a member of its own component closures built
// for it alone: fixed there, varying elsewhere.
std::optional<llvm::SmallVector<BindingTime>> appliesBuiltClosures(CallOp call);

// Raising.
std::optional<Elimination> consumerOf(CallOp call);
mlir::OwningOpRef<FuncOp> consumerFunction(CallOp call, const Elimination &consumer,
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

// Where a call's results go in its caller, read once per caller off its
// tails (tail::tailsOf): to its caller's return through a re-pack, a tail
// lost to a layout, which a copy returning them open makes a tail call; or
// anywhere else, a tail call's free way to the return among them.
enum class TailStanding : std::uint8_t { Elsewhere, LostToLayout };

// The calls of `fn` that are tails lost to a layout: each whose results
// reach `fn`'s return through a re-pack, read off its tails once.
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
llvm::SmallVector<ResultLayout> layoutsAsked(CallOp call, TailStanding standing);

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
// rule a key's results are made by (signatureOf) and its caller reads them
// by before the copy is built (keyCalls).
llvm::SmallVector<mlir::Type> keyedResults(FuncOp callee, llvm::ArrayRef<ResultLayout> layouts,
                                           identities::FactsView given,
                                           llvm::ArrayRef<std::optional<Hold>> passed);

// What a call wants, by kind: its signature copy where its index arguments
// fix a layout class the callee's layout changes under or a bare tensor
// argument's extent the callee names, as `site` lets a size key it, or it
// passes an argument at a hold its parameter does not have (each result
// that argument may reach, by the callee's published facts `given`, keyed
// with it), or `standing` is a tail lost to a layout, judged against what
// the copy `nodes` holds for its key gives; else its raise; else its
// pattern key. Keys and forms are interned in `nodes`' arena and table of
// forms.
mlir::FailureOr<std::optional<Want>> decide(Nodes &nodes, CallOp call, const Node *requester,
                                            FuncOp callee, FunctionId calleeId,
                                            const Node *calleeNode, identities::FactsView given,
                                            llvm::ArrayRef<BindingTime> seen,
                                            const CallSite &site, TailStanding standing);

// Calling a node.
llvm::SmallVector<mlir::Value> operandsOf(mlir::RewriterBase &rewriter, CallOp call,
                                          const PatternWant &want, const PatternKey &key,
                                          llvm::ArrayRef<Source> sources, FuncOp owner);
CallOp redirect(mlir::RewriterBase &rewriter, CallOp call, mlir::FlatSymbolRefAttr target,
                mlir::FunctionType type, IndexArgsAttr indices,
                llvm::ArrayRef<mlir::Value> operands);
CallOp redirect(mlir::RewriterBase &rewriter, CallOp call, mlir::FlatSymbolRefAttr target,
                mlir::FunctionType type, const RaiseWant &want);

} // namespace detail
} // namespace idr::specialize

#endif // IDR_TRANSFORMS_SPECIALIZE_CALLS_H
