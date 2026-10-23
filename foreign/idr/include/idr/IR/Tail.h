// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Tail position, the one fact `idr.call` holds as its TailKind: written on
// every call by the pass that makes it, kept by every pass that moves one
// as the place it moves it to gives, read off the function's tails by a
// pass that leaves a call where an op that holds no such fact stood
// (Optimize/Tails.h), and verified after every pass.
//
// A call in tail position never grows the stack: it becomes a loop, a
// jump to a join point, or LLVM's `musttail` under `tailcc`. So the fact
// is a promise the call keeps: `tail` demands the shape below, and a pass
// that puts anything after such a call breaks the program. And from the
// first-order program on, the fact is exactly where the call stands: a
// call in tail position left an ordinary call, or a self call the rule
// below admits left one, is a jump the compiler fails to make. The
// verifier reports either as an internal error. Where a function's tails
// are is read one way, down from its body (tailsOf), never up from an op.
//
// A self call modulo a context (`modulo_context`) is the second promise:
// its one result goes only into cells built for it whose value a tail
// returns, so idr-trmc builds those cells first, the field a hole, and the
// call fills the hole as its last act.
//
// A tail call and its caller lower to one return, so a tail call's result
// is laid out as its caller returns it. A re-pack (an op that gives its
// operand on but works to do so, converting between two layouts) is work
// after the value it takes, so no tail passes it; a call whose value
// reaches its function's return through one would be a tail but for the
// two layouts, and the verifier reports it as an internal error naming
// both, never as an ordinary call.
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
// a call whose result it takes may still be the tail: what `op` answers
// through the carrying interface (CarriesOnOpInterface). One that works
// does so after the call; one without the interface gives nothing on.
bool carriesOn(mlir::Operation *op);

// A tail of a function: an op whose results are what its function gives,
// each in its place, through ops that only give a value on, re-packs among
// them; `repack` is the first on the way that works to give it on,
// converting it between two layouts, and null where every one is free. A
// region op a break crosses (PropagateControlFlowBreak: the matches, the
// join points) is a tail when its results are, and so is the op each of
// its regions ends with in turn. An op that does something when its region
// ends (a lifetime's opener frees its memory there, an answer slot reads
// its results there) lets no break cross it, so nothing inside it is a
// tail.
struct Tail {
  mlir::Operation *source;
  mlir::Operation *repack;
};

// The tails of `fn`, read down from its body through each region op a break
// crosses, each region read once; none where the body ends in no return. A
// call among them with no re-pack is in tail position; one with a re-pack
// is a tail lost to a layout, which the specializer keys its callee's copy
// to its caller's layout for. The one reading of where a function's tails
// are: the verifier checks every call's fact against it, and a pass that
// asks where an op that holds no fact stands (an apply, a combination, a
// region op around a call) reads it once per function.
llvm::SmallVector<Tail> tailsOf(FuncOp fn);

// The ops of `fn` in tail position: its tails with no re-pack on the way.
// What a pass reads where it asks whether an op that holds no fact stands
// at a tail, once per function, and looks the op up among them.
llvm::SmallVector<mlir::Operation *> sourcesOf(FuncOp fn);

// The tails at and below `block`, which a pass knows ends a tail of its
// function with no re-pack after it: the function's body, or a block whose
// end the pass rewrote where it gave what its function gives. tailsOf
// reads them from the body.
llvm::SmallVector<Tail> tailsOf(mlir::Block &block);

// The blocks of `fn` where a tail ends: the body's, and down through each
// region op a break crosses whose results such a block gives on, every
// region whose end gives them to that op; each block whose terminator
// gives on something else. One walk down, each region read once.
llvm::SmallVector<mlir::Block *> tailEnds(FuncOp fn);

// The op whose results `block`'s terminator gives on unchanged, if one op
// gives them all. A re-pack there is that op, so a block that ends in one
// ends a tail with no call; a call whose value it re-packs is verify's to
// report.
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
// Through an op that gives the value on with no run-time work (carriesOn).
struct Through {
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
using Step = std::variant<Through, Into, ReadBack, Forward>;
// Before the hole, only an op the value passes through or a rejoin can
// take the call's result: a value laid out inline holds no hole.
using Approach = std::variant<Through, Forward>;

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

// Whether every call's fact in `fn`'s program is exactly where it stands,
// as it is from the stage where the program becomes first order on; before
// it, the frontend's `nontail` promises nothing. The one reading of the
// stage table for tail facts: a pass that must keep them exact, or may
// leave them, asks here.
bool decided(FuncOp fn);

// The fact of `call` where it ends no tail: `modulo_context` for a self call
// contextOf admits, `nontail` otherwise. What a pass that makes or moves a
// call writes where its place is no tail, so a call that became a self call
// there (its callee merged into its own function, its body moved into its
// callee's) takes the context the rule reads off it.
TailKind withContext(CallOp call);

// The parts of `call`'s fact the call alone can show: a `tail` call's
// results go unchanged to its block's terminator, which forwards them to
// its function's return or to the results of a region op a break crosses,
// and a re-pack on the way is reported with the two layouts it converts
// between; no operand of a `tail` or `modulo_context` call is, or lives
// in, a lifetime that ends with the call (this call's activation, or one
// opened around it), so no lifetime is handed over at a tail call;
// a `modulo_context` call is a self call contextOf admits, and once every
// fact is decided, a self call it admits is `modulo_context`. Called by
// idr.call's verifier.
mlir::LogicalResult verify(CallOp call);

// The part of every call's fact only its function can show: each `tail`
// call's block ends a tail of the function, and once every fact is
// decided, each call whose block ends one is `tail`, and no call's value
// reaches the function's return through a re-pack, which would make a
// tail of it but for the two layouts. Read off tailsOf, one walk down the
// regions a tail or a re-pack of one runs through, each region read once;
// called by idr.func's region verifier.
mlir::LogicalResult verify(FuncOp fn);

// The layout a `tail` call shares with its caller: each result of `call`
// is laid out as `caller` returns it, as families::layoutMatch says (the
// reading by which a reindex is free or re-packs), since the two lower to
// one return and a re-pack between them would run after the call. Called
// by idr.call's symbol-use verifier, beside the result components the two
// give back; a mismatch is an internal error naming both layouts.
mlir::LogicalResult verifyLayouts(CallOp call, FuncOp caller);

} // namespace idr::tail

namespace idr {

// `op` as a tail call: the call, when it is one whose fact is `tail`; null
// for any other op, and for a call that is `nontail` or `modulo_context`.
// The one reading of whether an op is a tail call, so a pass that treats
// tail calls apart asks here and never reads the fact itself.
CallOp tailCallOf(mlir::Operation *op);

// `op` as a call that is its caller's last act, which nothing of the
// caller may follow: a tail call, and a self call modulo a context, which
// fills its hole as its last act. Null for any other op, and for a call
// that returns to its caller (`nontail`), after which its caller goes on.
// The one reading of whether code may follow a call: a loan ended after
// it, or a lifetime's region closed after it.
CallOp lastActOf(mlir::Operation *op);

// `op` as a self call modulo a context: the call, when its fact is
// `modulo_context`, whose one result fills a hole in cells its context
// builds before it; null for any other op, and for a call that is `tail`
// or `nontail`. The one reading of which calls idr-trmc executes the
// context of, and of whether a pass left one where none may stand.
CallOp contextCallOf(mlir::Operation *op);

// Whether a call whose fact is `kind` returns to its caller, which goes on
// after it (`nontail`), rather than being its caller's last act. The one
// meaning of the kind for what may follow a call: lastActOf asks it of a
// call, and a reader of a kind held apart from its call asks it of the
// kind, as a row of the program graph holds one with no call op.
bool returnsToCaller(TailKind kind);

} // namespace idr

#endif // IDR_IR_TAIL_H
