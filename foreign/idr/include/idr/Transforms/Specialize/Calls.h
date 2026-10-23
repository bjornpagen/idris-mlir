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

// What a call wants, by kind: its signature copy where its index arguments
// fix a layout class the callee's layout changes under or a bare tensor
// argument's extent the callee names, as `site` lets a size key it, or it
// passes an argument at a hold its parameter does not have, or `standing`
// is a tail lost to a layout; else its raise; else its pattern key.
mlir::FailureOr<std::optional<Want>> decide(Arena &arena, Forms &forms, CallOp call,
                                            const Node *requester, FuncOp callee,
                                            FunctionId calleeId, const Node *calleeNode,
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
