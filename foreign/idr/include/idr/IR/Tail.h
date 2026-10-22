// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Tail position, the one fact `idr.call` holds as its TailKind: defined
// once, here, written on every call by the pass that makes the program
// first order and by every pass that makes or moves a call, or changes
// what follows one, and verified after every pass.
//
// A call in tail position never grows the stack: it becomes a loop, a
// jump to a join point, or LLVM's `musttail` under `tailcc`. So the fact
// is a promise the call keeps: `tail` demands the shape below, and a pass
// that puts anything after such a call breaks the program. And from the
// first-order program on, the fact is exactly decide's answer: a call in
// tail position left an ordinary call, or a self call the rule below
// admits left one, is a jump the compiler fails to make. The verifier
// reports either as an internal error. The frontend writes every call
// `nontail`, which promises nothing: no source syntax states a context,
// so it would only restate the decider. decide, run where the program
// becomes first order, writes `tail` and `modulo_context`.
//
// A self call modulo a context (`modulo_context`) is the second promise:
// its one result goes only into cells built for it whose value a tail
// returns, so idr-trmc builds those cells first, the field a hole, and the
// call fills the hole as its last act.
#ifndef IDR_IR_TAIL_H
#define IDR_IR_TAIL_H

#include "idr/IR/IdrDialect.h"

#include "mlir/IR/Operation.h"
#include "mlir/IR/Value.h"
#include "mlir/Support/LLVM.h"
#include "llvm/ADT/SmallVector.h"

#include <optional>
#include <variant>

namespace idr::tail {

// Whether `op` gives its operand's value on with no run-time work, so that
// a call whose result it takes may still be the tail: a change of grade
// (ResultCarriesOperand), or a reindex whose two types share a run-time
// layout. A reindex that re-packs is work after the call.
bool carriesOn(mlir::Operation *op);

// Whether what `op` gives is what its function gives: the ops after it in
// its block only give its results on (carriesOn), the block's terminator
// forwards exactly those values, and that terminator is the function's
// return, or ends a region of an op a control-flow break may cross
// (PropagateControlFlowBreak: the matches, the join points) and forwards
// them to that op's results, which give what the function gives in turn.
// An op that does something when its region ends (a lifetime's opener
// frees its memory there, an answer slot reads its results there) lets no
// break cross it, so nothing inside it is in tail position. The one
// definition of tail position. It reads up the regions above `op`; a
// verifier asks verify(FuncOp) instead, which reads each region once.
bool inTailPosition(mlir::Operation *op);

// The blocks of `fn` where a tail ends: the body's, and down through each
// region op a break crosses whose results such a block gives on, every
// region whose end gives them to that op; each block whose terminator
// gives on something else. One walk down, each region read once.
llvm::SmallVector<mlir::Block *> tailEnds(FuncOp fn);

// The op whose results `block`'s terminator gives on unchanged, if one op
// gives them all.
mlir::Operation *tailSource(mlir::Block &block);

// The op whose results `terminator` gives its operands to, one for one: the
// op whose region it ends, when a break may cross that op (nothing runs at
// its rejoin) and the terminator's one successor is the op's results. Null
// otherwise: for a jump into a join region, whose code goes on, for a
// terminator that never ends, and for the function's return.
mlir::Operation *rejoinOf(mlir::Operation *terminator);

// The steps of the path from a self call's result to the value its
// function returns. Each names the op that takes the path's value and the
// value it gives on.
//
// A change of grade, with no run-time form.
struct Regrade {
  mlir::Operation *op;
};
// Into field `field` of a value `op` builds for it, fresh: a cell, a
// constructor laid out inline, a closure's capture.
struct Into {
  mlir::Operation *op;
  unsigned operand;
  unsigned field;
  mlir::Value built;
};
// The part that holds the hole read back out of a value laid out inline.
struct ReadBack {
  mlir::Operation *op;
  mlir::Value part;
};
// From the end of a region to result `position` of its op, a match or a
// join point: the rejoin.
struct Forward {
  mlir::Operation *terminator;
  unsigned position;
};
using Step = std::variant<Regrade, Into, ReadBack, Forward>;
// Before the hole, only a change of grade or a rejoin can take the
// call's result: a value laid out inline holds no hole.
using Approach = std::variant<Regrade, Forward>;

// A self call modulo a context, as its rule reads it: the steps from its
// result to the cell field it fills (the hole, a cell laid out in memory,
// never one of a lexical lifetime), then from that cell to the value its
// function returns. Every value on the way is used by the next step alone,
// but where a value laid out inline has its other parts read; and every op
// the transformation builds before the call may run there (an IO action,
// a crash or a loop of the call's crosses no other). Read off the program
// as the frontend wrote it, before counting, and after it, where counting
// has kept it.
struct Context {
  CallOp call;
  llvm::SmallVector<Approach, 2> approach;
  Into hole;
  llvm::SmallVector<Step, 4> rest;
};

// `call`'s context, or none when the rule does not admit it.
std::optional<Context> contextOf(CallOp call);

// Whether every call's fact in `fn`'s program is decide's answer, as it is
// from the stage where the program becomes first order on; before it, the
// frontend's `nontail` promises nothing. The one reading of the stage
// table for tail facts: a pass that must keep them exact, or may leave
// them, asks here.
bool decided(FuncOp fn);

// What `call`'s place in its function makes it: `tail` in tail position;
// `modulo_context` for a self call contextOf admits; `nontail` otherwise.
// The pass that makes the program first order writes it on every call, and
// a pass that makes a call, moves one (contification, inlining,
// specialization) or changes what follows one writes what this gives at
// the call's place.
TailKind decide(CallOp call);

// The parts of `call`'s fact the call alone can show: a `tail` call's
// results go unchanged to its block's terminator, which forwards them to
// its function's return or to the results of a region op a break crosses;
// no operand of a `tail` or `modulo_context` call is, or lives in, a
// lifetime that ends with the call (this call's activation, or one opened
// around it), so no lifetime is handed over at a tail call;
// a `modulo_context` call is a self call contextOf admits, and once every
// fact is decided, a self call it admits is `modulo_context`. Called by
// idr.call's verifier.
mlir::LogicalResult verify(CallOp call);

// The part of every call's fact only its function can show: each `tail`
// call's block ends a tail of the function, and once every fact is
// decided, each call whose block ends one is `tail`. One walk down the
// regions in tail position, each region read once, called by idr.func's
// region verifier.
mlir::LogicalResult verify(FuncOp fn);

} // namespace idr::tail

#endif // IDR_IR_TAIL_H
