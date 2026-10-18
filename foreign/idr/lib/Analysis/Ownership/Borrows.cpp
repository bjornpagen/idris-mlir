// SPDX-License-Identifier: 0BSD
// Copyright (c) 2026 Bjorn Pagen
// Borrow inference: a parameter the function never needs a reference of
// its own for is borrowed, and its callers keep the reference, which saves
// an idr.dup and an idr.drop per call.
//
// Every parameter starts borrowed and becomes owned when it or a field read
// from it
//   - is taken apart (its cell is reused only if it is owned);
//   - is passed to an owned parameter of a call;
//   - is itself stored in a constructor;
//   - is returned, or forwarded on (a match's yield, the value a loop
//     carries round), which owns what it holds;
// and when an owned value is passed to it by a tail call from the same
// cycle of calls, which would otherwise have to drop its reference after
// the call, so that the call would no longer be a tail call. A self call
// whose result a tail position puts in a constructor counts as one:
// idr-trmc makes it a tail call that writes the field, unless a drop sits
// between the call and the constructor. An element read from a buffer
// takes a reference of its own where it is read: it is owned, and owning
// it asks nothing of the buffer.
// The program's root keeps its parameters owned: it is the program's one
// public function, whose caller is not a call this analysis sees. A
// parameter of quantity 1 is owned too: Idris proved the function uses it
// once, so it moves to that use and is never counted. A memo cell is never
// owned: a force writes it while its caller still reads it, so the
// dispatch that forces it reads a view.
//
// The inference is one analysis on MLIR's solver. Each parameter, and each
// value read from another, holds a state, which only ever goes from
// borrowed to owned. What a body needs on its own is owned when the
// analysis starts. What waits on another state reads it at the point after
// a call, which subscribes the call to it: a call's argument needs a
// reference of its own once its callee's parameter is owned, and a tail
// call within a cycle of calls owns its callee's parameter once the value
// it passes holds a reference of its own, which a parameter comes to when
// it is owned, and a field read from one when it needs a reference of its
// own. The solver visits a call again when a state it read changed, so
// the work is what changed; the states are finite and each changes once,
// so the solve ends, with the least set of owned parameters the rules
// close over, which does not depend on the order.
//
// The takes of reset/reuse are its decisions, not ops yet: each one owns
// its box.
#include "idr/Analysis/Ownership.h"

#include "idr/Analysis/CallCycles.h"
#include "idr/Analysis/Tail.h"
#include "idr/IR/Flow.h"
#include "idr/IR/Grades.h"
#include "idr/IR/IdrDialect.h"
#include "idr/IR/Ownership.h"

#include "mlir/Analysis/DataFlowFramework.h"

#include <cassert>
#include <variant>

using namespace mlir;
using idr::ownership::readThrough;
using idr::ownership::tracked;

namespace idr {

namespace {

// What inference holds of a parameter: nothing to hold, as it holds no
// references; owned whatever the function does with it (the root's, which
// its caller outside passes owned; one of quantity 1, which moves to its
// one use); a view whatever it does (a memo cell's); or borrowed until a
// use needs a reference of its own, and then owned. A value read from
// another is borrowed until it needs one, and then owned.
enum class Holding : uint8_t { Untracked, Fixed, View, Borrowed, Owned };

// What a parameter starts as, by its function and its type.
Holding startOf(FuncOp fn, Type type) {
  if (!holdsReferences(type))
    return Holding::Untracked;
  if (fn.isPublic())
    return Holding::Fixed;
  if (ownership::isMemoCell(type))
    return Holding::View;
  if (quantityOf(type) == Quantity::One)
    return Holding::Fixed;
  return Holding::Borrowed;
}

Borrows::Param paramOf(Holding held) {
  switch (held) {
  case Holding::Untracked:
    return Borrows::Param::Untracked;
  case Holding::Fixed:
  case Holding::Owned:
    return Borrows::Param::Owned;
  case Holding::View:
  case Holding::Borrowed:
    return Borrows::Param::Borrowed;
  }
  llvm_unreachable("a holding");
}

// Whether a parameter of that holding has a reference of its own.
bool ownsItself(Holding held) { return held == Holding::Fixed || held == Holding::Owned; }

// The holding of a parameter (its function's entry argument) or of a value
// read from another.
class HoldingState : public AnalysisState {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(HoldingState)
  using AnalysisState::AnalysisState;

  Holding holding() const { return held; }

  // A parameter's holding by its function and type, set when the analysis
  // starts, before anything reads it.
  ChangeResult start(Holding at) {
    if (held == at)
      return ChangeResult::NoChange;
    held = at;
    return ChangeResult::Change;
  }

  // A borrowed value needs a reference of its own; any other holding stays.
  ChangeResult own() {
    if (held != Holding::Borrowed)
      return ChangeResult::NoChange;
    held = Holding::Owned;
    return ChangeResult::Change;
  }

  void print(raw_ostream &os) const override {
    switch (held) {
    case Holding::Untracked:
      os << "untracked";
      return;
    case Holding::Fixed:
      os << "fixed";
      return;
    case Holding::View:
      os << "view";
      return;
    case Holding::Borrowed:
      os << "borrowed";
      return;
    case Holding::Owned:
      os << "owned";
      return;
    }
  }

private:
  Holding held = Holding::Borrowed;
};

// Whether `value` is a parameter: an argument of its function's body.
bool isParameter(Value value) {
  auto arg = dyn_cast<BlockArgument>(value);
  return arg && isa<FuncOp>(arg.getOwner()->getParentOp());
}

class Inference : public DataFlowAnalysis {
public:
  MLIR_DEFINE_EXPLICIT_INTERNAL_INLINE_TYPE_ID(Inference)

  Inference(DataFlowSolver &solver, const Reuses &reuses, const CallCycles &cycles,
            const SymbolTable &symbols)
      : DataFlowAnalysis(solver), reuses(reuses), cycles(cycles), symbols(symbols) {}

  // Every parameter starts, all before any is owned; then what each body
  // needs on its own is owned, and each call reads what it waits on.
  LogicalResult initialize(Operation *top) override {
    auto functions = cast<ProgramOp>(top).getOps<FuncOp>();
    for (FuncOp fn : functions)
      for (BlockArgument param : fn.getArguments()) {
        HoldingState *state = getOrCreate<HoldingState>(Value(param));
        propagateIfChanged(state, state->start(startOf(fn, param.getType())));
      }
    for (FuncOp fn : functions) {
      for (const Reuses::Site &site : reuses.sites(fn))
        if (const Value *box = std::get_if<Value>(&site.box))
          own(*box);
      fn.walk([&](Operation *op) { visitOp(op); });
    }
    return success();
  }

  // The point after a call, the only point a state is read at.
  LogicalResult visit(ProgramPoint *point) override {
    visitCall(cast<CallOp>(point->getPrevOp()));
    return success();
  }

private:
  void visitOp(Operation *op) {
    if (auto call = dyn_cast<CallOp>(op))
      return visitCall(call);
    // A constructor stores its fields: an unboxed sum's or an atom's in
    // idr.con, a box's in its cell by idr.cell.init.
    if (auto con = dyn_cast<ConOp>(op))
      return ownParameters(con.getFields());
    if (auto init = dyn_cast<CellInitOp>(op))
      return ownParameters(init.getFields());
    // Borrowed, a returned or forwarded parameter would need a reference
    // of its own to move on with, and the caller's value would be shared
    // from then on.
    if (isa<ReturnOp>(op))
      for (Value operand : op->getOperands())
        own(operand);
    forwardedValues(op, [&](OpOperand &operand, Value) { own(operand.get()); });
  }

  void ownParameters(ValueRange fields) {
    for (Value field : fields)
      if (isParameter(field))
        own(field);
  }

  // An argument passed to a parameter that owns itself needs a reference
  // of its own; a tail call within the cycle owns its callee's parameter
  // once the argument holds one. A call's callee is a function of the
  // program, with a parameter for each argument, as the call's verifier
  // holds.
  void visitCall(CallOp call) {
    ProgramPoint *after = getProgramPointAfter(call);
    auto callee = symbols.lookup<FuncOp>(call.getCalleeAttr().getAttr());
    auto fn = call->getParentOfType<FuncOp>();
    bool tail = cycles.together(callee, fn) &&
                (tail::inTailPosition(call) || tail::inTailPositionModuloConstructor(call));
    for (auto [arg, param] : llvm::zip_equal(call.getArgOperands(), callee.getArguments())) {
      if (ownsItself(getOrCreateFor<HoldingState>(after, Value(param))->holding()))
        own(arg);
      if (tail && holds(arg, after)) {
        HoldingState *state = getOrCreate<HoldingState>(Value(param));
        propagateIfChanged(state, state->own());
      }
    }
  }

  // Whether `value` holds a reference of its own, read at `after`: an
  // element or a value no read gives always does, one that holds no
  // reference never does, and otherwise the parameter it is or a value on
  // its way up to one does once its state says so. The way up is the
  // chain of what each was read from.
  bool holds(Value value, ProgramPoint *after) {
    for (Value at : definitionChain(value, readThrough)) {
      if (!tracked(at))
        return false;
      if (isParameter(at))
        return ownsItself(getOrCreateFor<HoldingState>(after, at)->holding());
      if (ownership::isCountedElement(at) || !readThrough(at))
        return true;
      if (getOrCreateFor<HoldingState>(after, at)->holding() == Holding::Owned)
        return true;
    }
    // A chain that closes on itself, in an unreachable block, reaches no
    // parameter and no value made outright.
    return false;
  }

  // `value` needs a reference of its own. An element has one already; a
  // field takes one, and so does what it was read from. Each step is to the
  // value read from, defined before it.
  void own(Value value) {
    if (!tracked(value) || ownership::isCountedElement(value))
      return;
    if (isParameter(value)) {
      HoldingState *state = getOrCreate<HoldingState>(value);
      propagateIfChanged(state, state->own());
      return;
    }
    std::optional<Value> from = readThrough(value);
    if (!from)
      return;
    HoldingState *state = getOrCreate<HoldingState>(value);
    ChangeResult changed = state->own();
    propagateIfChanged(state, changed);
    if (changed == ChangeResult::Change)
      own(*from);
  }

  const Reuses &reuses;
  const CallCycles &cycles;
  const SymbolTable &symbols;
};

} // namespace

Borrows::Borrows(Operation *program, AnalysisManager &am) {
  DataFlowSolver solver;
  solver.load<Inference>(am.getAnalysis<Reuses>(), am.getAnalysis<CallCycles>(),
                         am.getAnalysis<SymbolTable>());
  // MLIR's solver fails only where an analysis's visit does, and every
  // visit of the inference succeeds.
  [[maybe_unused]] LogicalResult ran = solver.initializeAndRun(program);
  assert(succeeded(ran) && "every visit of borrow inference succeeds");
  for (FuncOp fn : cast<ProgramOp>(program).getOps<FuncOp>()) {
    SmallVector<Param> &params = paramsOf[fn];
    for (BlockArgument param : fn.getArguments()) {
      Param each = paramOf(solver.lookupState<HoldingState>(Value(param))->holding());
      params.push_back(each);
      numBorrowed += each == Param::Borrowed ? 1 : 0;
    }
  }
}

} // namespace idr
